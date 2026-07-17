# PDFScrollPlayer - Cross Platform Version

An auto-scrolling PDF reader with tabs, keyboard shortcuts, and dark neon theme.

## Supported Platforms

| Platform | Architecture | Status |
|----------|-------------|--------|
| macOS    | ARM64 (Apple Silicon) | ✅ |
| macOS    | x86_64 (Intel) | ✅ |
| Windows  | x64 | ✅ |
| Linux    | x64 | ✅ |

## Quick Start

```bash
pip install -r requirements.txt
python pdf_scroll_player.py
```

## Building Executables

### macOS
```bash
# Build for current architecture
chmod +x build_macos.sh
./build_macos.sh

# Build universal binary (ARM64 + x86_64)
./build_macos.sh both
```

### Windows
```batch
build_windows.bat
```

### Linux
```bash
chmod +x build_linux.sh
./build_linux.sh
```

## Features

- Auto-scroll PDF at adjustable speed
- Multi-tab support (drag & drop or open dialog)
- Customizable keyboard shortcuts (⌘+, / Ctrl+,)
- Dark neon theme (same as macOS native version)
- Play/pause, speed control, direction toggle
- On-screen display (OSD) feedback
- Page number indicators

## Default Shortcuts

| Function | Key |
|----------|-----|
| Play/Pause | Space |
| Faster | Right |
| Slower | Left |
| Fast + | Ctrl+Right |
| Fast - | Ctrl+Left |
| Reset | R |
| Toggle Direction | S |
| Toggle Toolbar | H |
