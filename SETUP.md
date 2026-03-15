# VSCode + Godot Setup Guide

This guide will help you complete the setup for using VSCode with your Godot project.

## ✅ Already Done

- [x] AGENTS.md created with Copilot guidelines
- [x] .vscode/settings.json configured
- [x] .vscode/extensions.json created with recommended extensions

## 📋 Manual Steps Required

### 1. Install Godot Tools Extension in VSCode

1. Open VSCode
2. Press `Ctrl+Shift+X` to open Extensions
3. Search for "godot-tools"
4. Install the extension by **geequlim**
5. Reload VSCode if prompted

### 2. Update Godot Executable Path

1. Open [.vscode/settings.json](.vscode/settings.json)
2. Find the line: `"godot_tools.editor_path": "C:\\Path\\To\\Godot_v4.5_Engine.exe"`
3. Replace with the actual path to your Godot executable
   - Example: `"C:\\Users\\Gebruiker\\Programs\\Godot\\Godot_v4.5.exe"`
   - Or just `"godot"` if Godot is in your system PATH

### 3. Configure Godot Editor to Use VSCode

Open Godot Editor and configure the external editor:

1. Go to **Editor → Editor Settings**
2. Navigate to **Text Editor → External**
3. Check **"Use External Editor"**
4. Set **Exec Path** to your VSCode executable:
   ```
   C:\Users\Gebruiker\AppData\Local\Programs\Microsoft VS Code\Code.exe
   ```
   (Find your VSCode path with: `where code` in PowerShell)
5. Set **Exec Flags** to:
   ```
   {project} --goto {file}:{line}:{col}
   ```

### 4. Enable Godot Language Server (LSP)

This enables autocomplete and IntelliSense for GDScript:

1. In Godot Editor: **Editor → Editor Settings**
2. Navigate to **Network → Language Server**
3. Check **"Use Language Server"**
4. Set **Remote Host** to: `localhost`
5. Set **Remote Port** to: `6005`
6. Restart Godot Editor

### 5. Test the Integration

1. In Godot Editor, double-click any `.gd` script
2. It should open in VSCode automatically
3. Start typing in a GDScript file - you should see autocomplete suggestions
4. Hover over Godot functions - you should see documentation

## 🎯 Your Workflow

### Visual/Spatial Editing (Godot)

- Scene composition (adding nodes, positioning objects)
- 3D viewport navigation and object placement
- Inspector property editing
- Animation timeline editing
- Resource files (.tres) editing

### Code Editing (VSCode)

- Writing GDScript files (.gd)
- Shader code (.gdshader)
- Version control (Git)
- Using Copilot for code assistance
- Multi-file search and refactoring

### Tips

- **Save in VSCode** → Godot auto-reloads scripts (you'll see "Script Modified on Disk")
- **Use `Ctrl+Shift+P` in VSCode** → Type "Godot" to see available Godot-specific commands
- **Press `F1` in Godot** while hovering over GDScript to see documentation
- **In VSCode**, type `func` and let Copilot suggest complete functions

## 🤖 Using Copilot in This Project

With AGENTS.md in place, Copilot will:

- Understand you're working with Godot 4.5 and GDScript
- Follow Godot naming conventions and best practices
- Suggest complete, typed GDScript functions
- Understand your project's addons (Phantom Camera)
- Provide context-aware suggestions for game logic

### Example Prompts:

- "Create a state machine for player animations"
- "Add a health system with signals"
- "Implement enemy spawning with object pooling"
- "Create an interaction system for picking up items"

## 🔧 Troubleshooting

### Autocomplete not working?

- Verify Godot Language Server is running (check bottom-right of VSCode for "GDScript LSP")
- Restart both Godot and VSCode
- Check that port 6005 isn't blocked by firewall

### Scripts don't open in VSCode when double-clicked in Godot?

- Verify the VSCode path in Godot Editor Settings
- Check Exec Flags are exactly: `{project} --goto {file}:{line}:{col}`
- Try clicking "Open in External Editor" in Godot's script editor

### VSCode doesn't recognize .gd files?

- Make sure Godot Tools extension is installed and enabled
- Check `.vscode/settings.json` has file associations
- Reload VSCode window

## 📚 Resources

- [Godot Tools Extension Docs](https://github.com/godotengine/godot-vscode-plugin)
- [GDScript Style Guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
- [Godot 4.5 Documentation](https://docs.godotengine.org/en/stable/)
