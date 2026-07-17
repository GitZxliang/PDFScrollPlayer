@echo off
REM Build PDFScrollPlayer for Windows (x64)
REM Requires: Python 3.10+

cd /d "%~dp0"

REM Create and activate virtual environment
python -m venv venv
call venv\Scripts\activate.bat

REM Install dependencies
pip install -r requirements.txt --quiet

REM Build
pyinstaller --onefile --windowed --name "PDFScrollPlayer" ^
    --hidden-import PyQt6.sip ^
    --hidden-import fitz ^
    --noconfirm ^
    pdf_scroll_player.py

echo.
echo ✅ Build complete: dist\PDFScrollPlayer.exe
