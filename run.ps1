<#
.SYNOPSIS
Compiles and runs a C++ source file using g++, redirecting input from
'input.txt' and output to 'output.txt'.
.DESCRIPTION
This script simplifies the compile-and-run process for competitive programming
within a VS Code workspace. It assumes g++ is in the PATH and that
'input.txt' exists in the same directory. It creates 'output.txt'.
Errors during compilation or runtime are shown in the terminal.
.PARAMETER SourceFile
[Mandatory] The path to the C++ source file (e.g., 'main.cpp', 'problemA.cpp').
.PARAMETER CppStandard
[Optional] The C++ standard to use (e.g., 'c++17', 'c++20'). Defaults to 'c++17'.
.PARAMETER KeepExecutable
[Optional] Switch parameter. If present, the compiled executable file will not be deleted after execution.
.EXAMPLE
.\run_cpp.ps1 .\main.cpp
Compiles and runs main.cpp using C++17, reads from input.txt, writes to output.txt. Deletes main.exe afterwards.

.EXAMPLE
.\run_cpp.ps1 .\solution.cpp -CppStandard c++20 -KeepExecutable
Compiles and runs solution.cpp using C++20. Keeps solution.exe afterwards.

.NOTES
- Requires g++ to be available in the system PATH.
- Assumes input.txt is in the current directory or script execution directory.
- Will overwrite output.txt if it exists.
- Runtime errors (stderr) will appear in the terminal.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })] # Ensure the source file exists
    [string]$SourceFile,

    [Parameter(Mandatory=$false)]
    [string]$CppStandard = "c++17",

    [Parameter(Mandatory=$false)]
    [switch]$KeepExecutable
)

# --- Configuration ---
$InputFileName = "input.txt"
$OutputFileName = "output.txt"

# --- Helper Functions ---
function Test-CommandExists {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CommandName
    )
    $commandInfo = Get-Command $CommandName -ErrorAction SilentlyContinue
    return [bool]$commandInfo
}

# Determine paths relative to the source file's location or current dir
$SourceFileItem = Get-Item $SourceFile
$SourceDirectory = $SourceFileItem.DirectoryName
$BaseName = $SourceFileItem.BaseName # Filename without extension
$ExeFileName = "$BaseName.exe"
$ExeFilePath = Join-Path -Path $SourceDirectory -ChildPath $ExeFileName
$InputFilePath = Join-Path -Path $SourceDirectory -ChildPath $InputFileName
$OutputFilePath = Join-Path -Path $SourceDirectory -ChildPath $OutputFileName

# --- Pre-checks ---
if (-not (Test-CommandExists "g++")) {
    Write-Error "g++ command not found in PATH. Please ensure a C++ compiler (MinGW/g++) is installed and configured."
    Exit 1
}

if (-not (Test-Path $InputFilePath -PathType Leaf)) {
    Write-Warning "Input file '$InputFilePath' not found. Execution will proceed, but the program might fail if it expects input."
    # Optionally create an empty input file:
    # Set-Content -Path $InputFilePath -Value ""
    # Write-Warning "Created empty '$InputFilePath'."
}

# --- Compilation ---
Write-Host "Compiling '$($SourceFileItem.Name)' using '$CppStandard'..." -ForegroundColor Cyan
$CompileArgs = @(
    "-std=$CppStandard",
    "-Wall",            # Enable common warnings
    "-Wextra",          # Enable extra warnings
    "-g",               # Generate debugging symbols
    "$($SourceFileItem.FullName)", # Full path to source file, quoted
    "-o",
    "$ExeFilePath"  # Full path to output executable, quoted
    # Add any other desired compile flags here (e.g., -O2, -DLOCAL)
)

# Write-Verbose "g++ arguments: $CompileArgs" # Uncomment for debugging args
try {
    # Execute g++, redirect stderr to variable to check for warnings/errors even on success exit code (optional)
    # $compileOutput = g++ @CompileArgs 2>&1
    g++ @CompileArgs # Simpler, relies on $? and stderr appearing in console

    if (-not $?) { # Check if the last command (g++) succeeded
        Write-Error "Compilation Failed. Please check the errors above."
        Exit 1
    }
    # Optional: Check $compileOutput for warnings if needed
    Write-Host "Compilation Successful: '$ExeFileName' created." -ForegroundColor Green

} catch {
    Write-Error "An unexpected error occurred during compilation: $($_.Exception.Message)"
    Exit 1
}


# --- Execution ---
Write-Host "Executing '$ExeFileName'..." -ForegroundColor Cyan
Write-Host "(Input from '$InputFileName', Output to '$OutputFileName')"

try {
    # Use Get-Content to read input and pipe (|) to the executable.
    # Use > to redirect the executable's standard output to the output file.
    # Standard Error from the executable will still appear in the terminal.
    if (Test-Path $InputFilePath) {
        Get-Content $InputFilePath | & $ExeFilePath > $OutputFilePath
    } else {
        # If no input file, run without piping input
        & $ExeFilePath > $OutputFilePath
    }

    if (-not $?) {
        # Note: $? might be true even if the program had a runtime error (printed to stderr).
        # Relying on stderr is usually sufficient for runtime issues.
        Write-Warning "Execution finished, but the program might have exited with an error (check stderr output above)."
    } else {
        Write-Host "Execution Finished Successfully." -ForegroundColor Green
    }
    Write-Host "Output written to '$OutputFileName'."

} catch {
    Write-Error "An unexpected error occurred during execution: $($_.Exception.Message)"
    # Consider cleanup even on error? Maybe not, user might want to inspect executable.
    Exit 1
}

# --- Cleanup ---
if (($null -ne $ExeFilePath) -and (Test-Path $ExeFilePath) -and (-not $KeepExecutable.IsPresent)) {
     Write-Verbose "Removing executable '$ExeFileName'..."
     Remove-Item -Path $ExeFilePath -Force -ErrorAction SilentlyContinue # Best effort cleanup
} elseif ($KeepExecutable.IsPresent) {
      Write-Verbose "Keeping executable '$ExeFileName' as requested."
}

Write-Host "Script finished."