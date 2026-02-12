# PortaPath
<p align="left">
  <img width="386" height="291" alt="image" src="https://github.com/user-attachments/assets/a182ad40-f6b7-4deb-a59d-edf022c1e1eb" />
</p>
A Dynamic, Portable User Environment Variable Manager for Windows


## 🚀 The Problem
You have tools on a USB drive or external SSD (like FFmpeg, portable Python, or custom CLI tools). Every time you switch computers, you have to manually edit the System/User PATH or remember absolute path locations coupled with the drive letters—which can change from D: to E: to F: depending on the system.

## ✨ The Solution
PortaPath is a lightweight GUI tool that manages these variables for you. It resolves paths relative to the drive root, meaning it works regardless of which drive letter Windows assigns your device.

## 🛠️ Key Features
- **Lightweight**: This tool is contained within a single batch file while the configuration data is one json file.

- **Admin-Free**: Environment variables are modified on the User level, meaning no admin privilidges are needed.

- **Dynamic List Management**: View, add, remove, and edit entries via an interactable user interface.

- **Relative Path Resolution**: Automatically handles drive-letter shifts, saving you all the headache.

- **Instant Modification**: One-click "ACTIVATE" to update your User PATH and custom HOME variables.

- **Easy Cleanup**: "DEACTIVATE" scrubs all injected paths, leaving the host system exactly as you found it.


## 📦 Installation & Usage
1. **Download**: Clone this repo or download the .bat file.

2. **Configure**: Run the .bat file. Use the + button to add your tools.

3. **Browse**: Select the folder/program via the file explorer dialog, or enter path manually in the Folder Path section (drive letter not needed).

4. **Activate**: Click "ACTIVATE". Your system will now recognize those tools globally (terminals, IDEs, etc.).

5. **Save**: All settings are stored in portable_config.json for next time (automatically saves on Activate, or you can manually save anytime).
