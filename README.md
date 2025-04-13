# C++ Competitive Programming Workspace Setup Scripts

This repository contains PowerShell scripts to automate the setup and usage of a C++ competitive programming environment on Windows using Visual Studio Code.

## Scripts

1.  **`install-cpp.ps1`**:
    *   **Purpose**: Installs the necessary C++ compiler (`g++`) and debugger (`gdb`) using the [Scoop](https://scoop.sh/) package manager.
    *   **Prerequisites**: PowerShell 7+, Internet connection. Scoop will be installed if not found (may require changing PowerShell execution policy).
    *   **Usage**:
        ```powershell
        .\install-cpp.ps1
        ```
    *   **Notes**: Prioritizes user-level installation to avoid needing administrator privileges. Restarting the terminal might be necessary for PATH changes to take effect.

2.  **`configure-workspace.ps1`**:
    *   **Purpose**: Creates and configures a VS Code workspace folder specifically for C++ competitive programming. It sets up `.vscode` with recommended settings (`settings.json`), build tasks (`tasks.json`), debugging configurations (`launch.json`), and IntelliSense settings (`c_cpp_properties.json`). It also generates a `template.cpp`, `input.txt`, and `output.txt`.
    *   **Prerequisites**: `g++` and `gdb` installed and in PATH (use `install-cpp.ps1` first), VS Code installed with the `code` command available in PATH, VS Code C/C++ Extension (`ms-vscode.cpptools`) installed.
    *   **Usage**:
        *   Default (creates `./CP_Workspace`):
            ```powershell
            .\configure-workspace.ps1
            ```
        *   Specify path:
            ```powershell
            .\configure-workspace.ps1 -WorkspacePath "D:\Path\To\Your\Workspace"
            ```
    *   **Notes**: Will overwrite existing configuration files in `.vscode` if the workspace folder already exists. Attempts to auto-detect `g++` include paths for IntelliSense.

3.  **`run.ps1`**:
    *   **Purpose**: Compiles and runs a specific C++ source file. It uses `g++`, redirects standard input from `input.txt`, and redirects standard output to `output.txt` within the source file's directory.
    *   **Prerequisites**: `g++` installed and in PATH. An `input.txt` file should ideally exist in the same directory as the source file.
    *   **Usage**:
        ```powershell
        # Compile and run main.cpp with C++17 standard
        .\run.ps1 .\main.cpp

        # Compile and run solution.cpp with C++20 standard, keep the executable
        .\run.ps1 .\solution.cpp -CppStandard c++20 -KeepExecutable
        ```
    *   **Notes**: Assumes `input.txt` and the source file are in the same directory. Will overwrite `output.txt`. Compilation and runtime errors are shown in the terminal. The executable is deleted by default unless `-KeepExecutable` is specified.

## Recommended Workflow

1.  **Install Tools**: Run `.\install-cpp.ps1` to install `g++` and `gdb` via Scoop. Restart your terminal if prompted or if commands aren't found immediately.
2.  **Configure Workspace**: Run `.\configure-workspace.ps1` (optionally with `-WorkspacePath`) to create and set up your VS Code workspace folder. Open this folder in VS Code.
3.  **Code & Run**:
    *   Write your C++ code (e.g., in `template.cpp` or a new file).
    *   Place your test input in `input.txt`.
    *   Run your code using `.\run.ps1 .\your_source_file.cpp`.
    *   Check the results in `output.txt`.
    *   Use VS Code's debugging features (configured by `launch.json`). 