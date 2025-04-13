<#
.SYNOPSIS
Sets up a basic C++ competitive programming environment on Windows.
.DESCRIPTION
This script checks for and installs the MinGW-w64 `g++` compiler and the `gdb` debugger
using the Scoop package manager. It prioritizes user-level installation to avoid
requiring administrator privileges where possible. It also verifies that the
compiler and debugger are accessible via the system PATH.
.NOTES
- Requires PowerShell 7+ or later.
- Uses Scoop (https://scoop.sh/) for package management. If Scoop is not installed,
  the script will provide instructions to install it. Scoop installation might
  require adjusting the PowerShell execution policy.
- Administrator privileges are generally NOT required for Scoop installations,
  but they might be needed if you need to change the execution policy system-wide.
- Changes to the PATH environment variable by Scoop might require restarting
  your terminal or Windows session to take effect.
- This script installs the 'mingw' package from Scoop, which includes both g++ and gdb.
#>

# --- Configuration ---
# Package name in Scoop providing g++ and gdb
$MingwPackageName = "mingw"

# --- Helper Functions ---
function Test-CommandExists {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CommandName
    )
    # Check if a command is available in the current PATH
    # Use SilentlyContinue to avoid errors if the command is not found
    $commandInfo = Get-Command $CommandName -ErrorAction SilentlyContinue
    # Return $true if the command was found, $false otherwise
    return [bool]$commandInfo
}

function Test-IsAdmin {
    # Check if the script is running with Administrator privileges
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Script Start ---
Write-Host "Starting C++ Competitive Programming Environment Setup..." -ForegroundColor Cyan

# Check for Administrator Privileges (Informational)
if (Test-IsAdmin) {
    Write-Host "[INFO] Script is running with Administrator privileges." -ForegroundColor Green
} else {
    Write-Host "[INFO] Script is running without Administrator privileges. Attempting user-level installations." -ForegroundColor Yellow
}

# --- Step 1: Check and Install Scoop ---
Write-Host "`n--- Checking for Scoop Package Manager ---"
if (-not (Test-CommandExists "scoop")) {
    Write-Host "[WARN] Scoop package manager not found." -ForegroundColor Yellow
    Write-Host "Scoop is recommended for easy, user-level installation of developer tools."
    Write-Host "To install Scoop, open a new PowerShell window (NOT as Administrator) and run:"
    Write-Host 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser' -ForegroundColor Magenta
    Write-Host 'irm get.scoop.sh | iex' -ForegroundColor Magenta
    Write-Host "After installing Scoop, please re-run this script."
    # Optional: Add interactive prompt to attempt installation (requires careful handling of execution policy)
    $choice = Read-Host "Do you want to attempt to install Scoop now? (Requires internet connection and may change execution policy) [y/N]"
    if ($choice -eq 'y') {
        Write-Host "Attempting to install Scoop..." -ForegroundColor Yellow
        try {
            Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Invoke-Expression (Invoke-RestMethod get.scoop.sh)
            Write-Host "[SUCCESS] Scoop installation command executed. Please close and reopen PowerShell and run this script again." -ForegroundColor Green
            # Note: Scoop adds itself to the PATH, but it might not be available in the *current* session.
        } catch {
            Write-Host "[ERROR] Failed to install Scoop automatically. Please install it manually using the commands above." -ForegroundColor Red
            Write-Host "Error details: $($_.Exception.Message)"
            Exit 1
        }
    } else {
        Write-Host "Scoop installation skipped."
    }
    # Exit because subsequent steps depend on Scoop
    Exit 1
} else {
    Write-Host "[INFO] Scoop is installed." -ForegroundColor Green
    # Optional: Update Scoop and buckets
    Write-Host "Updating Scoop..."
    try {
        scoop update
        # Ensure the 'main' bucket (which contains mingw) is present
        if (-not (scoop bucket list | Select-String "main")) {
            Write-Host "Adding the main Scoop bucket..."
            scoop bucket add main
        }
    } catch {
        Write-Host "[WARN] Failed to update Scoop. Proceeding anyway. Details: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# --- Step 2: Check and Install C++ Compiler (g++) ---
Write-Host "`n--- Checking for g++ Compiler ---"
# We check for g++ specifically, as it's the target compiler.
if (-not (Test-CommandExists "g++")) {
    Write-Host "[INFO] g++ command not found. Attempting to install using Scoop..." -ForegroundColor Yellow

    # Check if the mingw package is already installed via Scoop, even if g++ isn't in PATH yet
    $mingwInstalled = scoop list | Where-Object { $_ -match $MingwPackageName }

    if ($mingwInstalled) {
         Write-Host "[WARN] Scoop indicates '$MingwPackageName' is installed, but g++ is not found in PATH." -ForegroundColor Yellow
         Write-Host "This might be a PATH issue. Try restarting your terminal or computer."
         Write-Host "You can also try running 'scoop reset $MingwPackageName' or 'scoop update $MingwPackageName'."
    } else {
        Write-Host "Installing '$MingwPackageName' package (includes g++ and gdb) via Scoop..."
        try {
            scoop install $MingwPackageName
            # Verify installation after attempting
            if (Test-CommandExists "g++") {
                Write-Host "[SUCCESS] g++ installed successfully via Scoop." -ForegroundColor Green
                g++ --version # Display version
            } else {
                Write-Host "[ERROR] Installation finished, but g++ command is still not found." -ForegroundColor Red
                Write-Host "Try restarting your terminal or check Scoop's installation logs."
                Exit 1
            }
        } catch {
            Write-Host "[ERROR] Failed to install '$MingwPackageName' using Scoop." -ForegroundColor Red
            Write-Host "Error details: $($_.Exception.Message)"
            Exit 1
        }
    }

} else {
    Write-Host "[INFO] g++ compiler is already available." -ForegroundColor Green
    g++ --version # Display version
}

# --- Step 3: Check for Debugger (gdb) ---
# gdb is usually included in the mingw package installed above.
Write-Host "`n--- Checking for gdb Debugger ---"
if (-not (Test-CommandExists "gdb")) {
    Write-Host "[WARN] gdb command not found." -ForegroundColor Yellow
    # Since mingw package includes gdb, if g++ was found but gdb wasn't, it's unusual.
    # It might indicate an incomplete installation or PATH issue.
    $mingwInstalled = scoop list | Where-Object { $_ -match $MingwPackageName }
    if ($mingwInstalled) {
         Write-Host "The '$MingwPackageName' package which should contain gdb seems installed."
         Write-Host "This might be a PATH issue. Try restarting your terminal or computer."
         Write-Host "You can also try running 'scoop reset $MingwPackageName'."
         # We don't exit here, as gdb is often considered optional for basic compilation.
    } else {
        Write-Host "The required '$MingwPackageName' package doesn't seem to be installed via Scoop."
        Write-Host "g++ might be installed from a different source."
        Write-Host "If you need gdb, consider installing the '$MingwPackageName' package using 'scoop install $MingwPackageName'."
    }
} else {
    Write-Host "[INFO] gdb debugger is available." -ForegroundColor Green
    gdb --version # Display version
}

# --- Step 4: Final Verification and Conclusion ---
Write-Host "`n--- Final Verification ---"
$gppFound = Test-CommandExists "g++"
$gdbFound = Test-CommandExists "gdb"

if ($gppFound) {
    Write-Host "[OK] g++ compiler is accessible." -ForegroundColor Green
} else {
    Write-Host "[FAIL] g++ compiler is NOT accessible. Manual intervention may be required (check PATH, restart terminal)." -ForegroundColor Red
}

if ($gdbFound) {
    Write-Host "[OK] gdb debugger is accessible." -ForegroundColor Green
} else {
    Write-Host "[WARN] gdb debugger is NOT accessible. Installation might be incomplete or PATH needs update." -ForegroundColor Yellow
}

Write-Host "`n--------------------------------------------------" -ForegroundColor Cyan
if ($gppFound) {
    Write-Host "C++ Competitive Programming Environment Setup Complete!" -ForegroundColor Green
    Write-Host "You should be able to compile C++ files using 'g++ your_file.cpp -o your_executable'"
     if ($gdbFound) {
         Write-Host "You should be able to debug using 'gdb your_executable'"
     }
    Write-Host "IMPORTANT: If commands don't work immediately, try restarting your PowerShell terminal or your computer." -ForegroundColor Yellow
} else {
    Write-Host "C++ Environment Setup encountered issues. Please review the messages above." -ForegroundColor Red
}
Write-Host "--------------------------------------------------" -ForegroundColor Cyan

# End of script