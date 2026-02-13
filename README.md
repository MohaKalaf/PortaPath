# PortaPath
<p align="left">
  <img width="386" height="291" alt="image" src="https://github.com/user-attachments/assets/a182ad40-f6b7-4deb-a59d-edf022c1e1eb" />
</p>
A Dynamic, Portable User Environment Variable Manager for Windows


## 🚀 The Problem
You have tools on a USB drive or external SSD (like FFmpeg, portable Python, or custom CLI tools). Every time you switch computers, you have to manually edit the System/User PATH or remember absolute path locations coupled with the drive letters—which can change from D: to E: to F: depending on the system.

## ✨ The Solution
PortaPath is a lightweight GUI/CLI tool that manages these variables for you. It resolves paths relative to the drive root, meaning it works regardless of which drive letter Windows assigns your device.

All settings are stored in a shared portapath_config.json, so you can switch between the GUI and CLI seamlessly.

## 🛠️ Key Features
- **Two Specialized Tools**: Use the GUI for easy visual management or the CLI for scripts and headless automation.
  
- **Smart Activation**: Checks if variables are already set before writing to the Registry, preventing unnecessary system broadcasts ("Registry Thrashing").
  
- **Lightweight**: This tool is contained within two batch files (or one if you only want to use GUI/CLI) while the configuration data is one json file.

- **Admin-Free**: Environment variables are modified on the User level, meaning no admin privilidges are needed.

- **Dynamic List Management**: View, add, remove, and edit entries via an interactable user interface.

- **Orphan Protection**: The deactivate command scans your drive for tools that were removed from the config but left active in the system, preventing "ghost" paths.

- **Relative Path Resolution**: Automatically handles drive-letter shifts, saving you all the headache.

- **Instant Modification**: One-click "ACTIVATE" to update your User PATH and custom HOME variables.

- **Easy Cleanup**: "DEACTIVATE" scrubs all injected paths, leaving the host system exactly as you found it.


## 📦 Installation
1. **Download**: Clone or download zip file from release page.

2. **Extract**: Extract the zip file to get both the GUI and CLI batch (.bat) files and save it to your desired drive.


## 🖥️ GUI Usage (`PortaPath.bat`)
Launch PortaPath.bat to open the visual interface.

1. **Add Tools**: Use the + button to create entries.

2. **Browse**: Select folders via the file picker (paths are automatically converted to relative).

3. **Env Var (Optional)**: Assign a variable name (e.g., JAVA_HOME) to a specific path.

4. **ACTIVATE**: Injects your tools into the User PATH immediately.

5. **DEACTIVATE**: Cleanly removes your tools from the Registry.

## ⌨️ CLI Usage (`PortaPath-CLI.bat`)
Use `PortaPath-CLI.bat` for rapid management or integration into startup scripts.

**Syntax**: `PortaPath-CLI.bat <command> [arguments]`

| Command | Arguments | Description |
|----------|------|------|
| list | None | Displays the current configuration table. |
| add | `[Label] [Path] [EnvVar]` | Adds a new tool. `EnvVar` is optional. |
| remove | `[Label]` | Removes a tool by its `Label` name. |
| activate | None | Injects variables into the system (skips duplicates). |
| deactivate | None | Removes variables. Includes an interactive check for orphaned/ghost paths. |

## CLI Example

```
:: Add Node.js (with a HOME variable)
PortaPath-CLI.bat add "NodeJS" "Apps\node-v18" "NODE_HOME"

:: Add a simple tool folder to PATH
PortaPath-CLI.bat add "FFmpeg" "Apps\ffmpeg\bin"

:: Inject into system
PortaPath-CLI.bat activate

:: Clean up before ejecting drive
PortaPath-CLI.bat deactivate
```
