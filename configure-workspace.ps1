<#
.SYNOPSIS
Configures a Visual Studio Code workspace for C++ Competitive Programming.
.DESCRIPTION
This script creates a specified folder and sets it up as a VS Code workspace.
It generates:
- A .vscode folder with recommended settings.json, tasks.json (for building),
  launch.json (for debugging), and c_cpp_properties.json (for IntelliSense).
- A basic template.cpp file.
- input.txt and output.txt files for local testing.
- Optionally, a cpp.json snippets file.
It assumes g++ and gdb are in the system PATH and the VS Code C/C++ extension is installed.
Attempts to auto-detect g++ system include paths for better IntelliSense configuration.
.PARAMETER WorkspacePath
The path where the workspace folder should be created. Defaults to './CP_Workspace'.
.EXAMPLE
.\Configure-VSCode-CP-Workspace.ps1
Creates the workspace in a 'CP_Workspace' subfolder in the current directory.

.EXAMPLE
.\Configure-VSCode-CP-Workspace.ps1 -WorkspacePath "D:\Work\CompetitiveProgramming"
Creates the workspace in the specified directory.

.NOTES
- Requires PowerShell 7+ or later.
- Requires VS Code 'code' command in PATH.
- Requires g++/gdb in PATH. The script relies on finding g++ in PATH for IntelliSense config.
- Requires VS Code C/C++ Extension (ms-vscode.cpptools).
- The script will overwrite existing configuration files in the .vscode folder
  if the workspace folder already exists.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$WorkspacePath = (Join-Path -Path $PSScriptRoot -ChildPath "CP_Workspace") # Default to CP_Workspace in script's dir or current dir if no $PSScriptRoot
)

# --- Helper Functions ---
function Test-CommandExists {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CommandName
    )
    $commandInfo = Get-Command $CommandName -ErrorAction SilentlyContinue
    return [bool]$commandInfo
}

function Get-GccSystemIncludePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CompilerCommandName = "g++"
    )

    Write-Verbose "Attempting to find system include paths for '$CompilerCommandName'..."
    $includePaths = [System.Collections.Generic.List[string]]::new()
    $compilerInfo = Get-Command $CompilerCommandName -ErrorAction SilentlyContinue

    if (-not $compilerInfo) {
        Write-Warning "Compiler command '$CompilerCommandName' not found in PATH. Cannot determine system include paths."
        return @{ CompilerFullPath = $CompilerCommandName; IncludePaths = $includePaths } # Return default name and empty list
    }

    # Prefer the 'Source' property if available, otherwise 'Path'
    $compilerFullPath = $compilerInfo.Source
    if ([string]::IsNullOrEmpty($compilerFullPath) -and $compilerInfo.Path) {
         $compilerFullPath = $compilerInfo.Path
    }

    # Ensure we have a full path
     if (-not [System.IO.Path]::IsPathRooted($compilerFullPath)) {
         # Sometimes Get-Command might return just the name if it's a function/alias before an exe
         $compilerInfoExe = Get-Command $CompilerCommandName -CommandType Application -ErrorAction SilentlyContinue
         if($compilerInfoExe) {
             $compilerFullPath = $compilerInfoExe.Source
             if ([string]::IsNullOrEmpty($compilerFullPath) -and $compilerInfoExe.Path) {
                 $compilerFullPath = $compilerInfoExe.Path
             }
         } else {
               Write-Warning "Could not resolve '$CompilerCommandName' to a full executable path. Using command name directly."
               $compilerFullPath = $CompilerCommandName # Fallback
         }
    }

     Write-Verbose "Using compiler path: $compilerFullPath"

     # --- Replace the ORIGINAL try block in Get-GccSystemIncludePaths with this one ---
     try {
        Write-Verbose "Executing compiler check: & '$compilerFullPath' -E -x c++ -v -"
        # Use direct invocation, provide empty stdin via pipe, merge Error stream (2) with Output stream (1) using 2>&1
        $output = "" | & $compilerFullPath -E -x c++ -v - 2>&1

        # Check PowerShell's automatic variable for the exit code of the last external command
        if ($LASTEXITCODE -ne 0) {
             Write-Warning "Executing '$compilerFullPath -v' failed with exit code $LASTEXITCODE. Cannot determine system include paths automatically."
             # Fallback: return the compiler path found, but an empty include list
             return @{ CompilerFullPath = $compilerFullPath.Replace('\','/'); IncludePaths = $includePaths }
        }

        # Parse the output (now in the $output variable, which is an array of strings)
        $startMarker = "#include <...> search starts here:"
        $endMarker = "End of search list."
        $capture = $false

        foreach ($line in $output) {
            # Handle potential variations in the start marker formatting
            if ($line -match '^[#]include\s+<\.\.\.>\s+search starts here:') {
                $capture = $true
                continue # Skip the marker line itself
            }
            if ($line -match [regex]::Escape($endMarker)) {
                $capture = $false
                break # Stop processing
            }
            if ($capture) {
                $path = $line.Trim()
                # Basic check to filter out non-path lines sometimes included
                if ($path -and ($path -match '^[a-zA-Z]:\\' -or $path -match '^/') -and (Test-Path $path -PathType Container -ErrorAction SilentlyContinue)) {
                    # Normalize path separators to forward slashes for JSON/VSCode compatibility
                    $normalizedPath = $path.Replace('\','/')
                    # Add recursive indicator for IntelliSense
                    $includePaths.Add("$normalizedPath/**")
                     Write-Verbose "Detected include path: $normalizedPath"
                } elseif($path -and $capture) {
                     Write-Verbose "Ignoring potential non-path line in include list: $path"
                }
            }
        }

         if($includePaths.Count -eq 0) {
              Write-Warning "Could not parse any include paths from '$compilerFullPath -v' output. IntelliSense might miss system headers. Output was:"
              # Optionally print a snippet of the captured output for diagnosis
              # $output | Select-Object -First 15 | ForEach-Object { Write-Warning " > $_" }
         }

    } catch {
        Write-Warning "An error occurred while trying to get system include paths for '$compilerFullPath': $($_.Exception.Message)"
        # Fallback on error: return the compiler path found, but an empty include list
        return @{ CompilerFullPath = $compilerFullPath.Replace('\','/'); IncludePaths = $includePaths }
    }
    # --- End of replaced block ---

    # Return both the resolved full path (with forward slashes) and the list of include paths
    # This line remains outside the replaced try..catch block
    return @{ CompilerFullPath = $compilerFullPath.Replace('\','/'); IncludePaths = $includePaths }
}


# --- Script Start ---
Write-Host "Starting VS Code C++ Competitive Programming Workspace Setup..." -ForegroundColor Cyan
Write-Host "Target Workspace Path: $WorkspacePath"

# --- Pre-requisite Checks ---
Write-Host "`n--- Checking Prerequisites ---"
$gppFound = $false
$codeCliFound = $false
$gdbFound = $false
$compilerData = $null
$CodeRunnerExtensionId = "formulahendry.code-runner" # ID for Code Runner

# Check for VS Code 'code' command
if (-not (Test-CommandExists "code")) {
    Write-Host "[ERROR] Visual Studio Code 'code' command not found in PATH." -ForegroundColor Red
    Write-Host "Please ensure VS Code is installed and added to your system's PATH."
    Write-Host "You might need to run the 'Shell Command: Install `code` command in PATH' command from within VS Code (Ctrl+Shift+P)."
    Exit 1
} else {
    Write-Host "[OK] VS Code 'code' command found." -ForegroundColor Green
    $codeCliFound = $true
}

# Check for g++ (assuming it's the desired compiler)
if (-not (Test-CommandExists "g++")) {
    Write-Host "[WARN] g++ compiler not found in PATH." -ForegroundColor Yellow
    Write-Host "The generated configuration relies on g++. Please ensure it's installed and in your PATH."
    $compilerData = @{ CompilerFullPath = "g++"; IncludePaths = @() } # Fallback defaults
} else {
    Write-Host "[OK] g++ compiler found." -ForegroundColor Green
    $gppFound = $true
    # Attempt to get compiler details for IntelliSense
    $compilerData = Get-GccSystemIncludePaths -CompilerCommandName "g++" -Verbose
}

# Check for gdb (assuming it's the desired debugger)
if (-not (Test-CommandExists "gdb")) {
    Write-Host "[WARN] gdb debugger not found in PATH." -ForegroundColor Yellow
    Write-Host "The generated debugging configuration relies on gdb. Please ensure it's installed and in your PATH."
     # Continue, but warn user debugging might fail
} else {
    Write-Host "[OK] gdb debugger found." -ForegroundColor Green
    $gdbFound = $true
}


# --- Install VS Code Extension (Code Runner) ---
if ($codeCliFound) {
    Write-Host "`n--- Checking/Installing VS Code Extension: Code Runner ---"
    $isCodeRunnerInstalled = $false
    try {
        # Get list of installed extensions, handle potential errors
        $installedExtensions = code --list-extensions --show-versions 2>&1 # Capture errors too
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to list VS Code extensions. Cannot check if Code Runner is installed. Error output:"
            $installedExtensions | ForEach-Object { Write-Warning " > $_" } # Display error details
        } else {
            # Check if Code Runner ID exists in the list (case-insensitive check)
             foreach ($ext in $installedExtensions) {
                if ($ext -match "^$([regex]::Escape($CodeRunnerExtensionId))(?:\@.*)?$") { # Match ID optionally followed by @version
                    $isCodeRunnerInstalled = $true
                    break
                }
            }
        }
    } catch {
        Write-Warning "An error occurred trying to list VS Code extensions: $($_.Exception.Message)"
        # Proceed assuming it might not be installed, or let the install command handle it
    }

    if ($isCodeRunnerInstalled) {
        Write-Host "[INFO] Code Runner extension ($CodeRunnerExtensionId) is already installed." -ForegroundColor Green
    } else {
        Write-Host "[INFO] Code Runner extension ($CodeRunnerExtensionId) not found. Attempting installation..." -ForegroundColor Yellow
        try {
            # Attempt to install the extension
            $installOutput = code --install-extension $CodeRunnerExtensionId 2>&1
            if ($LASTEXITCODE -ne 0) {
                 Write-Error "Failed to install Code Runner extension. Exit code: $LASTEXITCODE. Output:"
                 $installOutput | ForEach-Object { Write-Error " > $_" }
            } else {
                # Verify installation (optional, as install command usually shows success/failure)
                Write-Host "[SUCCESS] Attempted to install Code Runner. VS Code Output:" -ForegroundColor Green
                $installOutput | ForEach-Object { Write-Host " > $_"}
                Write-Host "Please restart VS Code if the extension doesn't appear immediately." -ForegroundColor Yellow
            }
        } catch {
             Write-Error "An error occurred trying to install Code Runner extension: $($_.Exception.Message)"
        }
    }
}

# --- Create Directories ---
Write-Host "`n--- Creating Workspace Structure ---"
# (Directory creation code remains the same as before)
try {
    # Create the main workspace folder
    if (-not (Test-Path -Path $WorkspacePath -PathType Container)) {
        New-Item -Path $WorkspacePath -ItemType Directory -Force | Out-Null
        Write-Host "[OK] Created workspace folder: $WorkspacePath" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Workspace folder already exists: $WorkspacePath" -ForegroundColor Yellow
    }

    # Create the .vscode subfolder
    $VscodeFolderPath = Join-Path -Path $WorkspacePath -ChildPath ".vscode"
    New-Item -Path $VscodeFolderPath -ItemType Directory -Force | Out-Null
    Write-Host "[OK] Ensured .vscode folder exists: $VscodeFolderPath" -ForegroundColor Green

} catch {
    Write-Host "[ERROR] Failed to create directory structure at '$WorkspacePath'." -ForegroundColor Red
    Write-Host "Error details: $($_.Exception.Message)"
    Exit 1
}

# --- Generate Configuration Files ---
Write-Host "`n--- Generating VS Code Configuration Files ---"

# --- settings.json ---
# (settings.json definition remains the same as before)
$SettingsJsonContent = @"
{
    // General settings for C++ Competitive Programming
    "files.associations": {
        "*.cpp": "cpp",
        "*.h": "cpp", // Associate .h with C++ too if needed
        "*.txt": "plaintext", // Ensure input/output are plain text
        "*.in": "plaintext",
        "*.out": "plaintext"
    },
    "editor.tabSize": 4,
    "editor.insertSpaces": true,
    "editor.detectIndentation": false,
    "editor.snippetSuggestions": "inline", // Show snippets inline with suggestions
    "editor.tabCompletion": "on", // Enable tab completion
    "editor.renderWhitespace": "boundary", // Show trailing whitespace
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,
    "files.eol": "\n", // Use LF line endings, common in CP platforms

    // C/C++ Extension specific settings
    "C_Cpp.default.cppStandard": "c++17", // Or "c++11", "c++14", "c++20"
    "C_Cpp.default.intelliSenseMode": "windows-gcc-x64", // Assumes 64-bit MinGW GCC
    "C_Cpp.formatting": "Default", // Use the default formatter from the extension
    "C_Cpp.vcFormat.indent.namespaceContents": true,

    // Optional: Settings for Code Runner extension (if installed)
    // "code-runner.executorMap": {
    //     "cpp": "cd $dir && g++ -std=c++17 -Wall -Wextra -pedantic $fileName -o $fileNameWithoutExt.exe && $fileNameWithoutExt.exe < input.txt > output.txt"
    // },
    // "code-runner.runInTerminal": true, // Recommended to see output/errors properly
    // "code-runner.saveFileBeforeRun": true,

    // Hide build output files from explorer
    "files.exclude": {
        "**/*.exe": true,
        "**/*.out": true, // Careful if you name your output file .out explicitly
        "**/*.o": true,
        "**/*.obj": true,
        "**/*.d": true
    }
}
"@
try {
    $SettingsJsonPath = Join-Path -Path $VscodeFolderPath -ChildPath "settings.json"
    Set-Content -Path $SettingsJsonPath -Value $SettingsJsonContent -Encoding UTF8 -Force
    Write-Host "[OK] Created/Updated settings.json" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to write settings.json: $($_.Exception.Message)" -ForegroundColor Red
}


# --- tasks.json ---
# (tasks.json definition remains the same as before)
$TasksJsonContent = @"
{
    // See https://go.microsoft.com/fwlink/?LinkId=733558
    // for the documentation about the tasks.json format
    "version": "2.0.0",
    "tasks": [
        {
            "label": "C/C++: g++ build active file",
            "type": "shell",
            "command": "g++", // Assumes g++ is in PATH
            "args": [
                "-std=c++17",      // Set C++ standard
                "-Wall",           // Enable common warnings
                "-Wextra",         // Enable extra warnings
                "-g",              // Generate debugging information
                "`${file}",        // Compile the currently open file
                "-o",
                "`${fileDirname}`\\`$({fileBasenameNoExtension}).exe" // Output executable (.exe) in the same directory
                // Add other flags as needed, e.g.:
                // "-O2",           // Optimization level
                // "-static"        // Static linking (if needed)
            ],
            "options": {
                "cwd": "`${fileDirname}"
            },
            "problemMatcher": [
                "`$gcc" // Use the standard GCC problem matcher
            ],
            "group": {
                "kind": "build",
                "isDefault": true // Make this the default build task (Ctrl+Shift+B)
            },
            "detail": "Compiler: g++"
        }
        // Add more tasks if needed, e.g., a task to run the compiled file
        // {
        //    "label": "Run compiled C++ file",
        //    "type": "shell",
        //    "command": "`${fileDirname}`\\`$({fileBasenameNoExtension}).exe",
        //    "args": [], // Add runtime args here if needed
        //    "options": {
        //        "cwd": "`${fileDirname}"
        //    },
        //    "dependsOn": "C/C++: g++ build active file", // Ensure file is built first
        //    "problemMatcher": [],
        //    "group": "test"
        // }
    ]
}
"@
try {
    $TasksJsonPath = Join-Path -Path $VscodeFolderPath -ChildPath "tasks.json"
    Set-Content -Path $TasksJsonPath -Value $TasksJsonContent -Encoding UTF8 -Force
    Write-Host "[OK] Created/Updated tasks.json" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to write tasks.json: $($_.Exception.Message)" -ForegroundColor Red
}


# --- launch.json ---
# (launch.json definition remains the same as before)
$LaunchJsonContent = @"
{
    // Use IntelliSense to learn about possible attributes.
    // Hover to view descriptions of existing attributes.
    // For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387
    "version": "0.2.0",
    "configurations": [
        {
            "name": "(gdb) Launch Active C++ File", // Name shown in the Debug dropdown
            "type": "cppdbg", // Type for C/C++ extension debugger
            "request": "launch",
            "program": "`${fileDirname}`\\`$({fileBasenameNoExtension}).exe", // Path to the executable
            "args": [], // Command line arguments to pass to the program
            "stopAtEntry": false, // Don't stop at the program's entry point automatically
            "cwd": "`${fileDirname}", // Set working directory to file's directory
            "environment": [], // Environment variables (leave empty usually)
            "externalConsole": false, // Use VS Code's integrated terminal (set to true for separate window)
            "MIMode": "gdb", // Debugger type
            "miDebuggerPath": "gdb", // Path to gdb. Assumes 'gdb' is in PATH. Change if needed.
                                     // Example: "C:/Users/YourUser/scoop/apps/mingw/current/bin/gdb.exe"
            "setupCommands": [
                {
                    "description": "Enable pretty-printing for gdb",
                    "text": "-enable-pretty-printing",
                    "ignoreFailures": true
                }
                // Optional: Redirect stdin from input.txt
                // Requires modifying the program path slightly if using external console,
                // or handling redirection within the debuggee if using integrated.
                // Simpler to manually copy/paste or run from terminal for CP.
            ],
            "preLaunchTask": "C/C++: g++ build active file" // Automatically build before debugging (matches task label)
        }
    ]
}
"@
try {
    $LaunchJsonPath = Join-Path -Path $VscodeFolderPath -ChildPath "launch.json"
    Set-Content -Path $LaunchJsonPath -Value $LaunchJsonContent -Encoding UTF8 -Force
    Write-Host "[OK] Created/Updated launch.json" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to write launch.json: $($_.Exception.Message)" -ForegroundColor Red
}


# --- c_cpp_properties.json (Modified Section) ---
# Prepare the includePath array for JSON
# Start with workspaceFolder
$includePathsJsonArray = @( '"${workspaceFolder}/**"' )
# Add detected system paths
if ($null -ne $compilerData.IncludePaths) {
    foreach ($path in $compilerData.IncludePaths) {
        # Paths are already formatted with /** and forward slashes
        $includePathsJsonArray += ('"{0}"' -f $path)
    }
}
# Join the array elements with commas and newlines+indentation for readability
$includePathJsonString = $includePathsJsonArray -join ",`n                "

# Get the compiler path (already has forward slashes from the function)
$compilerPathJsonString = $compilerData.CompilerFullPath

# Define content for .vscode/c_cpp_properties.json using the generated paths
$CppPropertiesJsonContent = @"
{
    "configurations": [
        {
            "name": "Win32-gcc", // Configuration name
            "includePath": [
                $includePathJsonString
            ],
            "defines": [
                "_DEBUG",
                "UNICODE",
                "_UNICODE"
                // Add common CP defines/macros if desired, e.g., "LOCAL"
            ],
            "compilerPath": "$compilerPathJsonString", // Use the detected full path or fallback name
            "cStandard": "c11",    // C standard (less relevant if only using C++)
            "cppStandard": "c++17", // C++ standard (match tasks.json)
            "intelliSenseMode": "windows-gcc-x64" // Or windows-gcc-x86 if using 32-bit MinGW
        }
    ],
    "version": 4 // Schema version
}
"@
try {
    $CppPropertiesJsonPath = Join-Path -Path $VscodeFolderPath -ChildPath "c_cpp_properties.json"
    Set-Content -Path $CppPropertiesJsonPath -Value $CppPropertiesJsonContent -Encoding UTF8 -Force
    Write-Host "[OK] Created/Updated c_cpp_properties.json (attempted auto-detection of includes)" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to write c_cpp_properties.json: $($_.Exception.Message)" -ForegroundColor Red
}


# --- Generate Template and I/O Files ---
# (Template and I/O file generation code remains the same as before)
Write-Host "`n--- Generating Template and I/O Files ---"
# Define content for template.cpp
$TemplateCppContent = @"
#include <iostream>
#include <vector>
#include <string>
#include <algorithm>
// Add other common headers like <cmath>, <numeric>, <set>, <map>, etc.

// Common practice: using namespace std;
// However, explicitly specifying std:: is often considered better practice.
using namespace std;

// Common macros (use with caution)
#define FAST_IO ios_base::sync_with_stdio(false); cin.tie(NULL);
#define ll long long
#define vi vector<int>
#define vll vector<long long>
#define pii pair<int, int>
#define pll pair<long long, long long>
// #define LOCAL // Uncomment for local debugging blocks

void solve() {
    // Read input for a single test case
    int n;
    cin >> n;
    cout << "Received input: " << n << endl;

    // Your solution logic here...
}

int main() {
    FAST_IO // Faster input/output

#ifdef LOCAL
    // Redirect input/output for local testing
    freopen("input.txt", "r", stdin);
    freopen("output.txt", "w", stdout);
#endif

    int t = 1; // Number of test cases
    // cin >> t; // Uncomment if there are multiple test cases
    while (t--) {
        solve();
    }

    return 0;
}
"@
try {
    $TemplateCppPath = Join-Path -Path $WorkspacePath -ChildPath "template.cpp"
    # Only create if it doesn't exist, don't overwrite user changes
    if (-not (Test-Path $TemplateCppPath)) {
        Set-Content -Path $TemplateCppPath -Value $TemplateCppContent -Encoding UTF8
        Write-Host "[OK] Created template.cpp" -ForegroundColor Green
    } else {
        Write-Host "[INFO] template.cpp already exists, skipping creation." -ForegroundColor Yellow
    }
} catch {
    Write-Host "[ERROR] Failed to write template.cpp: $($_.Exception.Message)" -ForegroundColor Red
}

# Create empty input.txt and output.txt
try {
    $InputTxtPath = Join-Path -Path $WorkspacePath -ChildPath "input.txt"
    $OutputTxtPath = Join-Path -Path $WorkspacePath -ChildPath "output.txt"

    if (-not (Test-Path $InputTxtPath)) {
        Set-Content -Path $InputTxtPath -Value "" -Encoding UTF8
        Write-Host "[OK] Created empty input.txt" -ForegroundColor Green
    } else {
         Write-Host "[INFO] input.txt already exists, skipping creation." -ForegroundColor Yellow
    }

    if (-not (Test-Path $OutputTxtPath)) {
        Set-Content -Path $OutputTxtPath -Value "" -Encoding UTF8
        Write-Host "[OK] Created empty output.txt" -ForegroundColor Green
     } else {
         Write-Host "[INFO] output.txt already exists, skipping creation." -ForegroundColor Yellow
    }
} catch {
     Write-Host "[ERROR] Failed to write input.txt or output.txt: $($_.Exception.Message)" -ForegroundColor Red
}


# --- Optional: Generate Snippets File ---
# (Snippets file generation code remains the same as before)
Write-Host "`n--- Generating Optional Snippets File ---"
# Define content for .vscode/cpp.json snippets
$SnippetsJsonContent = @'
{
    "CP Template Basic": {
        "prefix": "cptemplate",
        "body": [
            "#include <bits/stdc++.h>",
            "",
            "using namespace std;",
            "",
            "typedef long long ll;",
            "typedef vector<int> vi;",
            "typedef pair<int, int> pii;",
            "",
            "#define FAST_IO ios_base::sync_with_stdio(false); cin.tie(NULL);",
            "#define F first",
            "#define S second",
            "#define PB push_back",
            "#define MP make_pair",
            "#define REP(i, a, b) for (int i = a; i <= b; i++)",
            "",
            "void solve() {",
            "    $0",
            "}",
            "",
            "int main() {",
            "    FAST_IO",
            "",
            "    // #ifndef ONLINE_JUDGE",
            "    // freopen(\"input.txt\", \"r\", stdin);",
            "    // freopen(\"output.txt\", \"w\", stdout);",
            "    // #endif",
            "",
            "    int t = 1;",
            "    // cin >> t;",
            "    while (t--) {",
            "        solve();",
            "    }",
            "",
            "    return 0;",
            "}"
        ],
        "description": "Basic C++ Competitive Programming Template"
    },
    "For Loop": {
		"prefix": "fori",
		"body": [
			"for (int ${1:i} = 0; ${1:i} < ${2:n}; ++${1:i}) {",
			"\t$0",
			"}"
		],
		"description": "Standard 'for' loop"
	}
    // Add more snippets here
}
'@
try {
    $SnippetsJsonPath = Join-Path -Path $VscodeFolderPath -ChildPath "cpp.code-snippets"
    # Only create if it doesn't exist
     if (-not (Test-Path $SnippetsJsonPath)) {
        Set-Content -Path $SnippetsJsonPath -Value $SnippetsJsonContent -Encoding UTF8
        Write-Host "[OK] Created optional cpp.code-snippets snippets file." -ForegroundColor Green
     } else {
        Write-Host "[INFO] cpp.code-snippets snippets file already exists, skipping." -ForegroundColor Yellow
     }
} catch {
    Write-Host "[ERROR] Failed to write cpp.code-snippets: $($_.Exception.Message)" -ForegroundColor Red
}

#Copying the run.ps1 file to the workspace folder
$RunScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "run.ps1"
$RunScriptDestinationPath = Join-Path -Path $WorkspacePath -ChildPath "run.ps1"

try {
    if (-not (Test-Path $RunScriptDestinationPath)) {
        Copy-Item -Path $RunScriptPath -Destination $RunScriptDestinationPath -Force
        Write-Host "[OK] Copied run.ps1 to workspace folder." -ForegroundColor Green
    } else {
        Write-Host "[INFO] run.ps1 already exists in the workspace folder, skipping copy." -ForegroundColor Yellow
    }
} catch {
    Write-Host "[ERROR] Failed to copy run.ps1: $($_.Exception.Message)" -ForegroundColor Red
}

# --- Completion ---
# (Completion message and VS Code launch prompt remain the same as before)
Write-Host "`n--------------------------------------------------" -ForegroundColor Cyan
Write-Host "VS Code Workspace Setup Complete!" -ForegroundColor Green
Write-Host "Location: $WorkspacePath"
Write-Host "Configuration files (.vscode), template.cpp, input.txt, and output.txt have been generated."
Write-Host "Check '.vscode/c_cpp_properties.json' to see detected include paths."
Write-Host "You can now open this folder in VS Code."
Write-Host "--------------------------------------------------" -ForegroundColor Cyan

# Ask user if they want to open VS Code
$choice = Read-Host "Do you want to open the workspace folder '$WorkspacePath' in VS Code now? [Y/n]"
if ($choice -eq '' -or $choice -eq 'y' -or $choice -eq 'Y') {
    Write-Host "Opening VS Code..."
    # Use Start-Process -FilePath "code" -ArgumentList "." -WorkingDirectory $WorkspacePath for better control
    try {
       Push-Location -Path $WorkspacePath
       code .
       Pop-Location
       Write-Host "[OK] VS Code launched." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to launch VS Code: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "You can open it manually by navigating to '$WorkspacePath' and running 'code .'"
    }
} else {
    Write-Host "Skipping VS Code launch. You can open the folder manually:"
    Write-Host "cd '$WorkspacePath'"
    Write-Host "code . template.cpp input.txt output.txt"
}

# End of script