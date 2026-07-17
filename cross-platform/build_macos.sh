#!/bin/bash
# Build PDFScrollPlayer for macOS (ARM64 + x86_64)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Creating virtual environment..."
python3 -m venv venv 2>/dev/null
source venv/bin/activate

echo "Installing dependencies..."
pip install -r requirements.txt --quiet

ARCH_FLAG=""
APP_NAME="PDFScrollPlayer"
if [ "$1" = "both" ]; then
    ARCH_FLAG="--target-arch universal2"
    APP_NAME="PDFScrollPlayer-Universal"
fi

echo "Building $APP_NAME..."
pyinstaller --onefile --windowed --name "$APP_NAME" \
    --hidden-import PyQt6.sip \
    --hidden-import fitz \
    --noconfirm \
    pdf_scroll_player.py

# Create .app bundle
APP_BUNDLE="dist/$APP_NAME.app"
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>com.zxl.pdfscrollplayer</string>
    <key>CFBundleName</key><string>PDFScrollPlayer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "✅ Build complete: $APP_BUNDLE"
du -sh "$APP_BUNDLE"
