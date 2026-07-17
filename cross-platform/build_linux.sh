#!/bin/bash
# Build PDFScrollPlayer for Linux (x64)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Install system dependencies (Ubuntu/Debian)
if command -v apt-get &>/dev/null; then
    echo "Installing system dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3-pip python3-pyqt6 libgl1-mesa-glx 2>/dev/null || true
fi

python3 -m venv venv 2>/dev/null
source venv/bin/activate
pip install -r requirements.txt --quiet

pyinstaller --onefile --windowed --name "PDFScrollPlayer" \
    --hidden-import PyQt6.sip \
    --hidden-import fitz \
    --noconfirm \
    pdf_scroll_player.py

echo "✅ Build complete: dist/PDFScrollPlayer"
du -sh dist/PDFScrollPlayer
