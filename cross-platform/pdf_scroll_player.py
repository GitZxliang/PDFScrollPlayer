#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PDFScrollPlayer - Cross Platform Version
An auto-scrolling PDF reader with tabs, keyboard shortcuts, and dark neon theme.
Supports: Windows, macOS (Intel + ARM), Linux (x64)
"""

import sys, os, json, math, time, platform
from functools import partial
from typing import Optional, Callable

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QSlider, QLabel, QScrollArea, QFileDialog,
    QDialog, QDialogButtonBox, QListWidget, QListWidgetItem,
    QFrame, QSizePolicy, QToolTip, QMessageBox
)
from PyQt6.QtCore import (
    Qt, QTimer, QRect, QSize, QPoint, QPropertyAnimation,
    QEasingCurve, pyqtSignal, QByteArray, QEvent
)
from PyQt6.QtGui import (
    QColor, QPalette, QFont, QIcon, QAction, QKeySequence,
    QPixmap, QPainter, QImage, QLinearGradient, QBrush, QFontDatabase,
    QShortcut, QDragEnterEvent, QDropEvent, QTextOption, QTransform
)

try:
    import fitz  # PyMuPDF
except ImportError:
    fitz = None

# ============================================================
# Platform detection
# ============================================================
IS_WINDOWS = platform.system() == 'Windows'
IS_MACOS = platform.system() == 'Darwin'
IS_LINUX = platform.system() == 'Linux'
IS_ARM_MAC = IS_MACOS and platform.machine() == 'arm64'
IS_INTEL_MAC = IS_MACOS and platform.machine() in ('x86_64', 'amd64')

# ============================================================
# Config - Neon Dark Theme (same as original Swift version)
# ============================================================
class Config:
    BAR_HEIGHT = 56
    MIN_SPEED = 0.1
    MAX_SPEED = 5.0
    SPEED_STEP = 0.1
    FAST_SPEED_STEP = 0.5
    SCROLL_LINE_STEP = 80
    SCROLL_PAGE_PERCENT = 0.8
    OSD_DURATION = 1200  # ms
    
    # Colors - matching the original Swift version
    NEON_BLUE = QColor(76, 153, 255)
    NEON_CYAN = QColor(51, 217, 255)
    NEON_GREEN = QColor(51, 255, 153)
    NEON_RED = QColor(255, 64, 89)
    DARK_BG = QColor(15, 20, 36)
    CARD_BG = QColor(26, 33, 56)
    SURFACE_BG = QColor(36, 43, 66)
    DIM_TEXT = QColor(115, 115, 115)

    @staticmethod
    def apply_dark_theme(app: QApplication):
        app.setStyle('Fusion')
        palette = QPalette()
        palette.setColor(QPalette.ColorRole.Window, Config.DARK_BG)
        palette.setColor(QPalette.ColorRole.WindowText, Qt.GlobalColor.white)
        palette.setColor(QPalette.ColorRole.Base, Config.CARD_BG)
        palette.setColor(QPalette.ColorRole.AlternateBase, Config.SURFACE_BG)
        palette.setColor(QPalette.ColorRole.Text, Qt.GlobalColor.white)
        palette.setColor(QPalette.ColorRole.Button, Config.CARD_BG)
        palette.setColor(QPalette.ColorRole.ButtonText, Qt.GlobalColor.white)
        palette.setColor(QPalette.ColorRole.Highlight, Config.NEON_BLUE)
        palette.setColor(QPalette.ColorRole.HighlightedText, Qt.GlobalColor.white)
        app.setPalette(palette)
        
        # Style sheet for custom widgets
        app.setStyleSheet(f"""
            QToolTip {{ background-color: {Config.CARD_BG.name()}; color: white; border: 1px solid {Config.NEON_BLUE.name()}; border-radius: 4px; padding: 4px; }}
            QSlider::groove:horizontal {{ background: {Config.SURFACE_BG.name()}; height: 4px; border-radius: 2px; }}
            QSlider::handle:horizontal {{ background: {Config.NEON_CYAN.name()}; width: 14px; height: 14px; margin: -5px 0; border-radius: 7px; }}
            QSlider::sub-page:horizontal {{ background: {Config.NEON_BLUE.name()}; border-radius: 2px; }}
            QScrollBar:horizontal {{ background: {Config.CARD_BG.name()}; height: 6px; }}
            QScrollBar::handle:horizontal {{ background: {Config.SURFACE_BG.name()}; min-width: 30px; border-radius: 3px; }}
            QScrollBar:vertical {{ background: {Config.CARD_BG.name()}; width: 6px; }}
            QScrollBar::handle:vertical {{ background: {Config.SURFACE_BG.name()}; min-height: 30px; border-radius: 3px; }}
            QFileDialog {{ background-color: {Config.DARK_BG.name()}; color: white; }}
        """)


# ============================================================
# ShortcutManager
# ============================================================
class ShortcutManager:
    CONFIG_FILE = os.path.join(os.path.expanduser('~'), '.pdfscrollplayer_shortcuts.json')
    
    DEFAULTS = {
        'play': 'Space', 'faster': 'Right', 'slower': 'Left',
        'fast_faster': 'Ctrl+Right', 'fast_slower': 'Ctrl+Left',
        'page_up': 'Up', 'page_down': 'Down',
        'scroll_up': 'Shift+Up', 'scroll_down': 'Shift+Down',
        'reset': 'R', 'toggle_ui': 'H', 'direction': 'S',
        'next_tab': 'Alt+Tab', 'prev_tab': 'Alt+Shift+Tab',
        'speed_1': '1', 'speed_2': '2', 'speed_3': '3', 'speed_5': '5', 'speed_10': '0'
    }
    
    LABELS = {
        'play': '播放/暂停', 'faster': '加速', 'slower': '减速',
        'fast_faster': '快速加速', 'fast_slower': '快速减速',
        'page_up': '上一页', 'page_down': '下一页',
        'scroll_up': '向上滚动', 'scroll_down': '向下滚动',
        'reset': '重置', 'toggle_ui': '切换界面', 'direction': '切换方向',
        'next_tab': '下一个页签', 'prev_tab': '上一个页签',
        'speed_1': '速度 1x', 'speed_2': '速度 2x', 'speed_3': '速度 3x',
        'speed_5': '速度 5x', 'speed_10': '速度 10x'
    }
    
    def __init__(self):
        self.shortcuts = dict(self.DEFAULTS)
        self.load()
    
    def load(self):
        try:
            with open(self.CONFIG_FILE, 'r') as f:
                data = json.load(f)
                self.shortcuts.update(data)
        except:
            pass
    
    def save(self):
        try:
            with open(self.CONFIG_FILE, 'w') as f:
                json.dump(self.shortcuts, f, indent=2)
        except:
            pass
    
    def get(self, action: str) -> str:
        return self.shortcuts.get(action, self.DEFAULTS.get(action, ''))
    
    def set(self, action: str, key: str):
        self.shortcuts[action] = key
        self.save()
    
    def reset_all(self):
        self.shortcuts = dict(self.DEFAULTS)
        self.save()
    
    @staticmethod
    def format_key(key_str: str) -> str:
        if IS_MACOS:
            return ShortcutManager.format_key_mac(key_str)
        else:
            return ShortcutManager.format_key_win(key_str)
    
    @staticmethod
    def format_key_mac(key_str: str) -> str:
        parts = key_str.lower().split('+')
        mapping = {
            'ctrl': '⌃', 'shift': '⇧', 'alt': '⌥', 'meta': '⌘',
            'space': '空格', 'tab': 'Tab', 'left': '←', 'right': '→',
            'up': '↑', 'down': '↓', 'escape': 'Esc', 'enter': '↵',
            'pageup': 'Page↑', 'pagedown': 'Page↓',
            'backspace': '⌫', 'delete': '⌦'
        }
        result = []
        for p in parts:
            if p in mapping:
                result.append(mapping[p])
            else:
                result.append(p.upper())
        return ''.join(result)
    
    @staticmethod
    def format_key_win(key_str: str) -> str:
        parts = key_str.split('+')
        mapping = {
            'ctrl': 'Ctrl', 'shift': 'Shift', 'alt': 'Alt', 'meta': 'Win',
            'space': 'Space', 'tab': 'Tab', 'left': '←', 'right': '→',
            'up': '↑', 'down': '↓', 'escape': 'Esc', 'enter': 'Enter',
            'pageup': 'PgUp', 'pagedown': 'PgDn',
        }
        result = []
        for p in parts:
            p_lower = p.lower()
            if p_lower in mapping:
                result.append(mapping[p_lower])
            else:
                result.append(p.upper())
        return ' + '.join(result)

# ============================================================
# PDFTab - Tab data
# ============================================================
class PDFTab:
    def __init__(self, filepath: str):
        self.filepath = filepath
        self.filename = os.path.basename(filepath)
        self.scroll_pos = 0.0
        self.speed = 1.0
        self.is_playing = False
        self.doc = None
        self.page_count = 0
        self.load()
    
    def load(self):
        if fitz is None:
            raise RuntimeError("PyMuPDF not installed. Run: pip install PyMuPDF")
        self.doc = fitz.open(self.filepath)
        self.page_count = len(self.doc)
    
    def get_page_pixmap(self, page_num: int, scale: float = 1.5) -> Optional[QImage]:
        if not self.doc or page_num < 0 or page_num >= self.page_count:
            return None
        page = self.doc[page_num]
        mat = fitz.Matrix(scale, scale)
        pix = page.get_pixmap(matrix=mat)
        img = QImage(pix.samples, pix.width, pix.height, pix.stride, QImage.Format.Format_RGB888)
        return img

# ============================================================
# OSDWidget - On Screen Display overlay
# ============================================================
class OSDWidget(QLabel):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.ToolTip |
                          Qt.WindowType.WindowStaysOnTopHint | Qt.WindowType.NoDropShadowWindowHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setStyleSheet("background: transparent;")
        self.hide()
        self._timer = QTimer(self)
        self._timer.setSingleShot(True)
        self._timer.timeout.connect(self._fade_out)
        self._opacity = 1.0
    
    def show_message(self, text: str, color: QColor = Config.NEON_CYAN, duration: int = 1200):
        self.setText(text)
        self.setStyleSheet(f"""
            background-color: {Config.CARD_BG.name()};
            color: {color.name()};
            font-size: 20px;
            font-weight: bold;
            padding: 12px 24px;
            border: 2px solid {color.name()}40;
            border-radius: 12px;
        """)
        self.adjustSize()
        
        if self.parent() and self.parent().window():
            parent_geo = self.parent().window().geometry()
            x = parent_geo.x() + (parent_geo.width() - self.width()) // 2
            y = parent_geo.y() + (parent_geo.height() - self.height()) // 2 - 60
            self.move(x, y)
        
        self.setWindowOpacity(1.0)
        self.show()
        self.raise_()
        self._timer.start(duration)
    
    def _fade_out(self):
        self.hide()



# ============================================================
# PDFViewWidget - PDF rendering and scrolling
# ============================================================
class PDFViewWidget(QScrollArea):
    SCALE = 1.5  # Render scale
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.content = QWidget()
        self.content_layout = QVBoxLayout(self.content)
        self.content_layout.setContentsMargins(0, 0, 0, 0)
        self.content_layout.setSpacing(0)
        
        self.setWidget(self.content)
        self.setWidgetResizable(True)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.setStyleSheet(f"""
            QScrollArea {{ background-color: {Config.DARK_BG.name()}; border: none; }}
        """)
        
        self._page_labels: list[QLabel] = []
        self._tab: Optional[PDFTab] = None
        self._total_height = 0
        self._page_heights: list[int] = []
        self._cached_pixmaps: dict[int, QPixmap] = {}
        self._current_width = 0
        self._last_render_pos = -1
    
    def set_tab(self, tab: Optional[PDFTab]):
        self._tab = tab
        self._cached_pixmaps.clear()
        self._page_labels.clear()
        self._page_heights.clear()
        self._total_height = 0
        
        # Clear layout
        while self.content_layout.count():
            item = self.content_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        
        if tab is None:
            self._show_empty_state()
            return
        
        self._render_pages()
    
    def _show_empty_state(self):
        """Show empty state similar to macOS PDFCanvas"""
        self.content.setMinimumSize(400, 300)
        self.content.setStyleSheet(f"""
            background: qlineargradient(x1:0, y1:0, x2:0, y2:1,
                stop:0 {Config.DARK_BG.name()}, stop:1 {QColor(20, 30, 60).name()});
        """)
    
    def _render_pages(self):
        if not self._tab or not self._tab.doc:
            return
        
        viewport_width = self.viewport().width() if self.viewport().width() > 100 else 800
        pw = viewport_width - 40  # padding
        scale = pw / (self._tab.doc[0].rect.width if self._tab.doc.page_count > 0 else 612)
        
        self._page_heights = []
        self._total_height = 0
        
        for i in range(self._tab.page_count):
            try:
                page = self._tab.doc[i]
                page_rect = page.rect
                ph = int(page_rect.height * scale)
                pw_actual = int(page_rect.width * scale)
                
                # Label for each page
                label = QLabel()
                label.setFixedWidth(pw_actual)
                label.setMinimumHeight(ph)
                label.setStyleSheet("background: transparent;")
                label.setAlignment(Qt.AlignmentFlag.AlignTop)
                label.setCursor(Qt.CursorShape.IBeamCursor)
                
                # Page number indicator
                num_label = QLabel(f"  — {i+1} —")
                num_label.setFixedHeight(28)
                num_label.setStyleSheet(f"color: {Config.DIM_TEXT.name()}; font-size: 11px; background: transparent;")
                num_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
                
                self.content_layout.addWidget(num_label)
                self.content_layout.addWidget(label)
                
                self._page_labels.append(label)
                self._page_heights.append(ph)
                self._total_height += ph + 28
                
                # Render this page
                self._render_page(i, scale)
            except:
                continue
    
    def _render_page(self, page_num: int, scale: float):
        if not self._tab or not self._tab.doc:
            return
        try:
            page = self._tab.doc[page_num]
            mat = fitz.Matrix(scale, scale)
            pix = page.get_pixmap(matrix=mat)
            img = QImage(pix.samples, pix.width, pix.height, pix.stride, QImage.Format.Format_RGB888)
            px = QPixmap.fromImage(img)
            self._cached_pixmaps[page_num] = px
            
            if page_num < len(self._page_labels):
                self._page_labels[page_num].setPixmap(px)
        except:
            pass
    
    def resizeEvent(self, event):
        super().resizeEvent(event)
        if self._tab and self._tab.doc:
            self._render_pages()
    
    def scroll_to(self, pos: float):
        """Scroll to a specific position (0.0 to 1.0)"""
        max_scroll = self.verticalScrollBar().maximum()
        self.verticalScrollBar().setValue(int(pos * max_scroll))
    
    def get_scroll_pos(self) -> float:
        max_scroll = max(1, self.verticalScrollBar().maximum())
        return self.verticalScrollBar().value() / max_scroll

# ============================================================
# TabBar - Bottom tab bar widget
# ============================================================
class TabBar(QFrame):
    tab_clicked = pyqtSignal(int)
    tab_close_clicked = pyqtSignal(int)
    add_clicked = pyqtSignal()
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self._tabs: list[str] = []
        self._active = -1
        self._tab_widgets: list[QWidget] = []
        self.setFixedHeight(36)
        self.setStyleSheet(f"""
            TabBar {{ background-color: {Config.CARD_BG.name()}; border: none; }}
        """)
        self._layout = QHBoxLayout(self)
        self._layout.setContentsMargins(4, 2, 40, 2)
        self._layout.setSpacing(4)
        
        # Add button (always at the end via space)
        self._add_btn = QPushButton("+")
        self._add_btn.setFixedSize(30, 28)
        self._add_btn.setStyleSheet(f"""
            QPushButton {{ background: transparent; color: {Config.NEON_CYAN.name()}; font-size: 16px; 
                           font-weight: bold; border: none; border-radius: 4px; }}
            QPushButton:hover {{ background: {Config.SURFACE_BG.name()}; }}
        """)
        self._add_btn.clicked.connect(self.add_clicked.emit)
        self._add_btn.setToolTip("添加PDF")
    
    def set_tabs(self, filenames: list[str], active: int):
        self._tabs = filenames
        self._active = active
        self._rebuild()
    
    def _rebuild(self):
        # Remove existing tab widgets
        for w in self._tab_widgets:
            self._layout.removeWidget(w)
            w.deleteLater()
        self._tab_widgets.clear()
        
        for i, name in enumerate(self._tabs):
            is_active = (i == self._active)
            tab = QFrame()
            tab.setFixedHeight(28)
            tab.setCursor(Qt.CursorShape.PointingHandCursor)
            
            if is_active:
                tab.setStyleSheet(f"""
                    QFrame {{ background-color: {Config.NEON_BLUE.name()}40; border: 1px solid {Config.NEON_BLUE.name()}80;
                              border-radius: 6px; }}
                """)
            else:
                tab.setStyleSheet(f"""
                    QFrame {{ background-color: rgba(255,255,255,12); border: 0.5px solid rgba(255,255,255,15);
                              border-radius: 6px; }}
                    QFrame:hover {{ background-color: rgba(255,255,255,20); }}
                """)
            
            tab_layout = QHBoxLayout(tab)
            tab_layout.setContentsMargins(8, 0, 4, 0)
            tab_layout.setSpacing(4)
            
            # Click handler
            tab.mousePressEvent = lambda e, idx=i: self.tab_clicked.emit(idx)
            
            # Label
            display_name = name[:-4] if name.lower().endswith('.pdf') else name
            if len(display_name) > 18:
                display_name = display_name[:16] + '...'
            
            lbl = QLabel(display_name)
            lbl.setStyleSheet(f"color: {'white' if is_active else '#b0b0b0'}; font-size: 11px; background: transparent;")
            tab_layout.addWidget(lbl, 1)
            
            # Close button
            close_btn = QPushButton("×")
            close_btn.setFixedSize(20, 20)
            close_btn.setStyleSheet(f"""
                QPushButton {{ background: transparent; color: #777; border: none; border-radius: 10px; font-size: 14px; }}
                QPushButton:hover {{ background: {Config.NEON_RED.name()}; color: white; }}
            """)
            close_btn.clicked.connect(lambda checked, idx=i: self.tab_close_clicked.emit(idx))
            tab_layout.addWidget(close_btn)
            
            self._layout.addWidget(tab)
            self._tab_widgets.append(tab)
        
        # Spacer to push add button to right
        self._layout.addStretch(1)
        self._layout.addWidget(self._add_btn)



# ============================================================
# Toolbar - Top toolbar widget
# ============================================================
class Toolbar(QFrame):
    play_clicked = pyqtSignal()
    faster_clicked = pyqtSignal()
    slower_clicked = pyqtSignal()
    reset_clicked = pyqtSignal()
    direction_clicked = pyqtSignal()
    open_clicked = pyqtSignal()
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedHeight(Config.BAR_HEIGHT)
        self._is_playing = False
        self._is_down = True
        self._speed = 1.0
        self._setup_ui()
    
    def _setup_ui(self):
        layout = QHBoxLayout(self)
        layout.setContentsMargins(12, 0, 12, 0)
        
        # Logo
        logo = QLabel("PDFScrollPlayer")
        logo.setStyleSheet("color: white; font-size: 14px; font-weight: bold; background: transparent;")
        layout.addWidget(logo)
        layout.addSpacing(16)
        
        # Play/Pause button
        self.play_btn = QPushButton("▶")
        self.play_btn.setFixedSize(36, 30)
        btn_style = f"""
            QPushButton {{ background: {Config.SURFACE_BG.name()}; color: white; border: none; border-radius: 4px; font-size: 14px; }}
            QPushButton:hover {{ background: {Config.NEON_BLUE.name()}; }}
        """
        self.play_btn.setStyleSheet(btn_style)
        self.play_btn.clicked.connect(self.play_clicked.emit)
        self.play_btn.setToolTip("播放/暂停 (空格)")
        layout.addWidget(self.play_btn)
        layout.addSpacing(8)
        
        # Speed slider
        self.slider = QSlider(Qt.Orientation.Horizontal)
        self.slider.setMinimum(int(Config.MIN_SPEED * 100))
        self.slider.setMaximum(int(Config.MAX_SPEED * 100))
        self.slider.setValue(int(self._speed * 100))
        self.slider.setFixedWidth(120)
        self.slider.valueChanged.connect(self._on_slider)
        layout.addWidget(self.slider)
        layout.addSpacing(6)
        
        # Speed label
        self.speed_label = QLabel("1.00x")
        self.speed_label.setFixedWidth(60)
        self.speed_label.setStyleSheet(f"color: {Config.NEON_CYAN.name()}; font-size: 14px; font-weight: bold; background: transparent;")
        self.speed_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(self.speed_label)
        layout.addSpacing(6)
        
        # - button
        slow_btn = QPushButton("−")
        slow_btn.setFixedSize(28, 28)
        slow_btn.setStyleSheet(btn_style)
        slow_btn.clicked.connect(self.slower_clicked.emit)
        slow_btn.setToolTip("减速")
        layout.addWidget(slow_btn)
        
        # + button
        fast_btn = QPushButton("+")
        fast_btn.setFixedSize(28, 28)
        fast_btn.setStyleSheet(btn_style)
        fast_btn.clicked.connect(self.faster_clicked.emit)
        fast_btn.setToolTip("加速")
        layout.addWidget(fast_btn)
        
        # ↩ button (Reset)
        reset_btn = QPushButton("↩")
        reset_btn.setFixedSize(28, 28)
        reset_btn.setStyleSheet(btn_style)
        reset_btn.clicked.connect(self.reset_clicked.emit)
        reset_btn.setToolTip("重置 (R)")
        layout.addWidget(reset_btn)
        
        # Direction button
        self.dir_btn = QPushButton("↑")
        self.dir_btn.setFixedSize(28, 28)
        self.dir_btn.setStyleSheet(btn_style)
        self.dir_btn.clicked.connect(self.direction_clicked.emit)
        self.dir_btn.setToolTip("方向 (S)")
        layout.addWidget(self.dir_btn)
        
        # Spacer
        layout.addStretch(1)
        
        # Status label
        self.status_label = QLabel("未打开PDF")
        self.status_label.setStyleSheet(f"color: {Config.DIM_TEXT.name()}; font-size: 12px; background: transparent;")
        layout.addWidget(self.status_label)
    
    def _on_slider(self, val):
        self._speed = val / 100.0
        self.speed_label.setText(f"{self._speed:.2f}x")
    
    def set_playing(self, playing: bool):
        self._is_playing = playing
        self.play_btn.setText("⏸" if playing else "▶")
    
    def set_speed(self, speed: float):
        self._speed = speed
        self.slider.setValue(int(speed * 100))
        self.speed_label.setText(f"{speed:.2f}x")
    
    def set_direction(self, is_down: bool):
        self._is_down = is_down
        self.dir_btn.setText("↑" if is_down else "↓")
    
    def set_status(self, text: str):
        self.status_label.setText(text)

# ============================================================
# ShortcutEditor Dialog
# ============================================================
class ShortcutEditor(QDialog):
    def __init__(self, shortcut_mgr: ShortcutManager, parent=None):
        super().__init__(parent)
        self.mgr = shortcut_mgr
        self.setWindowTitle("自定义快捷键")
        self.setFixedSize(480, 520)
        self.setStyleSheet(f"background-color: {Config.DARK_BG.name()}; color: white;")
        
        layout = QVBoxLayout(self)
        title = QLabel("快捷键设置")
        title.setStyleSheet(f"color: {Config.NEON_CYAN.name()}; font-size: 18px; font-weight: bold;")
        layout.addWidget(title)
        
        # Key capture list
        self.list_widget = QListWidget()
        self.list_widget.setStyleSheet(f"""
            QListWidget {{ background: {Config.CARD_BG.name()}; border: none; border-radius: 8px; }}
            QListWidget::item {{ padding: 6px; border-bottom: 1px solid {Config.SURFACE_BG.name()}; }}
        """)
        
        for action, label in ShortcutManager.LABELS.items():
            item = QListWidgetItem(f"{label}  →  {ShortcutManager.format_key(self.mgr.get(action))}")
            item.setData(Qt.ItemDataRole.UserRole, action)
            self.list_widget.addItem(item)
        
        layout.addWidget(self.list_widget)
        
        # Buttons
        btn_layout = QHBoxLayout()
        
        save_btn = QPushButton("保存")
        save_btn.setStyleSheet(f"""
            QPushButton {{ background: {Config.NEON_BLUE.name()}; color: white; border: none; 
                          border-radius: 4px; padding: 8px 20px; font-weight: bold; }}
            QPushButton:hover {{ background: {Config.NEON_CYAN.name()}; }}
        """)
        save_btn.clicked.connect(self.accept)
        btn_layout.addWidget(save_btn)
        
        close_btn = QPushButton("关闭")
        close_btn.setStyleSheet("color: white; border: 1px solid #555; border-radius: 4px; padding: 8px 20px;")
        close_btn.clicked.connect(self.reject)
        btn_layout.addWidget(close_btn)
        
        reset_btn = QPushButton("恢复默认")
        reset_btn.setStyleSheet("color: #aaa; border: 1px solid #555; border-radius: 4px; padding: 8px 20px;")
        reset_btn.clicked.connect(self._reset)
        btn_layout.addWidget(reset_btn)
        
        layout.addLayout(btn_layout)
    
    def _reset(self):
        self.mgr.reset_all()
        self._refresh_list()
    
    def _refresh_list(self):
        for i in range(self.list_widget.count()):
            item = self.list_widget.item(i)
            action = item.data(Qt.ItemDataRole.UserRole)
            if action:
                item.setText(f"{ShortcutManager.LABELS.get(action, action)}  →  {ShortcutManager.format_key(self.mgr.get(action))}")
    
    def keyPressEvent(self, event):
        # Capture the key press to set shortcut
        current = self.list_widget.currentItem()
        if current:
            action = current.data(Qt.ItemDataRole.UserRole)
            if action:
                key = self._event_to_key(event)
                if key and key.lower() != 'escape':
                    self.mgr.set(action, key)
                    self._refresh_list()
    
    def _event_to_key(self, event) -> str:
        mods = []
        if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            mods.append('Ctrl')
        if event.modifiers() & Qt.KeyboardModifier.ShiftModifier:
            mods.append('Shift')
        if event.modifiers() & Qt.KeyboardModifier.AltModifier:
            mods.append('Alt')
        if event.modifiers() & Qt.KeyboardModifier.MetaModifier:
            mods.append('Meta' if IS_MACOS else 'Win')
        
        key = event.key()
        key_map = {
            Qt.Key.Key_Space: 'Space', Qt.Key.Key_Tab: 'Tab',
            Qt.Key.Key_Left: 'Left', Qt.Key.Key_Right: 'Right',
            Qt.Key.Key_Up: 'Up', Qt.Key.Key_Down: 'Down',
            Qt.Key.Key_PageUp: 'PageUp', Qt.Key.Key_PageDown: 'PageDown',
            Qt.Key.Key_Escape: 'Escape', Qt.Key.Key_Return: 'Enter',
            Qt.Key.Key_Backspace: 'Backspace', Qt.Key.Key_Delete: 'Delete'
        }
        
        if key in key_map:
            key_name = key_map[key]
        else:
            key_char = QKeySequence(key).toString()
            if key_char and len(key_char) == 1:
                key_name = key_char
            else:
                return ''
        
        if mods:
            return '+'.join(mods) + '+' + key_name
        return key_name



# ============================================================
# MainWindow
# ============================================================
class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("PDFScrollPlayer")
        self.setMinimumSize(700, 500)
        self.setAcceptDrops(True)
        
        # Core data
        self.shortcut_mgr = ShortcutManager()
        self.tabs: list[PDFTab] = []
        self.active_tab_index = -1
        self._is_playing = False
        self._speed = 1.0
        self._is_scrolling_down = True
        self._timer = QTimer(self)
        self._timer.timeout.connect(self._tick)
        self._timer.setInterval(33)  # ~30fps
        self._shortcut_actions = {}
        
        # Central widget
        central = QWidget()
        central.setStyleSheet(f"background-color: {Config.DARK_BG.name()};")
        self.setCentralWidget(central)
        main_layout = QVBoxLayout(central)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)
        
        # Toolbar (top)
        self.toolbar = Toolbar()
        self.toolbar.play_clicked.connect(self.toggle_play)
        self.toolbar.faster_clicked.connect(lambda: self.adjust_speed(Config.SPEED_STEP))
        self.toolbar.slower_clicked.connect(lambda: self.adjust_speed(-Config.SPEED_STEP))
        self.toolbar.reset_clicked.connect(self.reset_scroll)
        self.toolbar.direction_clicked.connect(self.toggle_direction)
        self.toolbar.open_clicked.connect(self.open_pdf)
        main_layout.addWidget(self.toolbar)
        
        # PDF View (middle)
        self.pdf_view = PDFViewWidget()
        main_layout.addWidget(self.pdf_view, 1)
        
        # Tab Bar (bottom)
        self.tab_bar = TabBar()
        self.tab_bar.tab_clicked.connect(self.switch_to_tab)
        self.tab_bar.tab_close_clicked.connect(self.close_tab)
        self.tab_bar.add_clicked.connect(self.open_pdf)
        main_layout.addWidget(self.tab_bar)
        
        # OSD overlay
        self.osd = OSDWidget()
        
        # Setup shortcuts
        self._setup_shortcuts()
        
        # Restore window geometry
        screen = QApplication.primaryScreen().geometry()
        w, h = min(1200, int(screen.width() * 0.8)), min(900, int(screen.height() * 0.85))
        x, y = (screen.width() - w) // 2, (screen.height() - h) // 2
        self.setGeometry(x, y, w, h)
    
    def _setup_shortcuts(self):
        self._shortcut_actions = {}
        
        def make_handler(action: str):
            def handler():
                shortcut = self.shortcut_mgr.get(action)
                if shortcut:
                    self._handle_match(action)
            return handler
        
        # Map actions to shortcut keys
        for action in ShortcutManager.DEFAULTS:
            shortcut = self.shortcut_mgr.get(action)
            if not shortcut:
                continue
            
            # Convert shortcut to QShortcut
            qkey = self._to_qkey(shortcut)
            if qkey:
                s = QShortcut(qkey, self)
                s.activated.connect(make_handler(action))
                self._shortcut_actions[action] = s
    
    def _to_qkey(self, shortcut: str):
        """Convert shortcut string (e.g., 'Ctrl+Right') to QKeySequence"""
        if not shortcut:
            return None
        parts = shortcut.split('+')
        qt_parts = []
        for p in parts:
            p_lower = p.lower()
            mapping = {
                'ctrl': 'Ctrl', 'shift': 'Shift', 'alt': 'Alt',
                'meta': 'Meta', 'win': 'Meta',
                'space': 'Space', 'tab': 'Tab',
                'left': 'Left', 'right': 'Right',
                'up': 'Up', 'down': 'Down',
                'pageup': 'PageUp', 'pagedown': 'PageDown',
                'escape': 'Escape', 'enter': 'Enter',
                'backspace': 'Backspace', 'delete': 'Del'
            }
            if p_lower in mapping:
                qt_parts.append(mapping[p_lower])
            else:
                qt_parts.append(p.upper())
        
        key_str = '+'.join(qt_parts)
        seq = QKeySequence(key_str)
        if seq.isEmpty():
            return None
        return seq
    
    def _handle_match(self, action: str):
        """Handle shortcut action - mirror of the Swift version's installKeyboardMonitor"""
        handler_map = {
            'play': self.toggle_play,
            'faster': lambda: self.adjust_speed(Config.SPEED_STEP),
            'slower': lambda: self.adjust_speed(-Config.SPEED_STEP),
            'fast_faster': lambda: self.adjust_speed(Config.FAST_SPEED_STEP),
            'fast_slower': lambda: self.adjust_speed(-Config.FAST_SPEED_STEP),
            'page_up': lambda: self._scroll_by(-self.pdf_view.viewport().height() * Config.SCROLL_PAGE_PERCENT),
            'page_down': lambda: self._scroll_by(self.pdf_view.viewport().height() * Config.SCROLL_PAGE_PERCENT),
            'scroll_up': lambda: self._scroll_by(-Config.SCROLL_LINE_STEP),
            'scroll_down': lambda: self._scroll_by(Config.SCROLL_LINE_STEP),
            'reset': self.reset_scroll,
            'toggle_ui': self.toggle_toolbar,
            'direction': self.toggle_direction,
            'next_tab': self._next_tab,
            'prev_tab': self._prev_tab,
        }
        
        # Speed shortcuts
        speed_map = {'speed_1': 1, 'speed_2': 2, 'speed_3': 3, 'speed_5': 5, 'speed_10': 10}
        
        if action in handler_map:
            handler_map[action]()
        elif action in speed_map:
            self.set_speed(speed_map[action])
    
    def _scroll_by(self, dy: float):
        scrollbar = self.pdf_view.verticalScrollBar()
        val = scrollbar.value() + int(dy)
        val = max(scrollbar.minimum(), min(scrollbar.maximum(), val))
        scrollbar.setValue(val)
    
    def _next_tab(self):
        if len(self.tabs) > 1 and self.active_tab_index >= 0:
            self.switch_to_tab((self.active_tab_index + 1) % len(self.tabs))
    
    def _prev_tab(self):
        if len(self.tabs) > 1 and self.active_tab_index >= 0:
            self.switch_to_tab((self.active_tab_index - 1 + len(self.tabs)) % len(self.tabs))
    
    # ===================== Tab Management =====================
    
    def open_pdf(self):
        files, _ = QFileDialog.getOpenFileNames(self, "选择PDF文件", "", "PDF文件 (*.pdf)")
        for fp in files:
            self._open_file(fp)
    
    def _open_file(self, filepath: str):
        if not os.path.exists(filepath) or not filepath.lower().endswith('.pdf'):
            return
        try:
            tab = PDFTab(filepath)
            self.tabs.append(tab)
            self.switch_to_tab(len(self.tabs) - 1)
            self._update_tab_bar()
            self.osd.show_message(f"已加载 {tab.page_count} 页", Config.NEON_GREEN, 1000)
        except Exception as e:
            self.osd.show_message(f"加载失败: {str(e)}", Config.NEON_RED, 2000)
    
    def switch_to_tab(self, idx: int):
        if idx < 0 or idx >= len(self.tabs) or idx == self.active_tab_index:
            return
        self._save_current_tab_state()
        self._stop()
        self.active_tab_index = idx
        tab = self.tabs[idx]
        
        # Update PDF view
        self.pdf_view.set_tab(tab)
        self.toolbar.set_speed(tab.speed)
        self._is_scrolling_down = True
        self.toolbar.set_direction(True)
        
        self.toolbar.set_status(f"{tab.filename}  {tab.page_count}页")
        self.setWindowTitle(f"{tab.filename} - PDFScrollPlayer")
        
        self._update_tab_bar()
        
        if tab.is_playing:
            self._start()
    
    def close_tab(self, idx: int):
        if idx < 0 or idx >= len(self.tabs):
            return
        self._stop()
        del self.tabs[idx]
        
        if not self.tabs:
            self.active_tab_index = -1
            self.pdf_view.set_tab(None)
            self.toolbar.set_status("未打开PDF")
            self.setWindowTitle("PDFScrollPlayer")
            self._update_tab_bar()
        else:
            if idx <= self.active_tab_index:
                self.active_tab_index = max(0, self.active_tab_index - 1)
            self._update_tab_bar()
            self.switch_to_tab(self.active_tab_index)
    
    def _update_tab_bar(self):
        filenames = [t.filename for t in self.tabs]
        self.tab_bar.set_tabs(filenames, self.active_tab_index)
    
    def _save_current_tab_state(self):
        if 0 <= self.active_tab_index < len(self.tabs):
            tab = self.tabs[self.active_tab_index]
            tab.speed = self._speed
            tab.is_playing = self._is_playing
            tab.scroll_pos = self.pdf_view.get_scroll_pos()
    
    # ===================== Playback =====================
    
    def toggle_play(self):
        if not self.tabs or self.active_tab_index < 0:
            self.osd.show_message("请先打开PDF", QColor(255, 165, 0), 1000)
            return
        if self._is_playing:
            self._stop()
        else:
            self._start()
    
    def _start(self):
        if self.active_tab_index < 0 or self.active_tab_index >= len(self.tabs):
            return
        self._is_playing = True
        self.tabs[self.active_tab_index].is_playing = True
        self.toolbar.set_playing(True)
        self._timer.start()
        self.osd.show_message("播放中", Config.NEON_GREEN, 600)
    
    def _stop(self):
        if 0 <= self.active_tab_index < len(self.tabs):
            self.tabs[self.active_tab_index].is_playing = False
            self._save_current_tab_state()
        self._is_playing = False
        self.toolbar.set_playing(False)
        self._timer.stop()
        if self.tabs:
            self.osd.show_message("已暂停", Config.NEON_CYAN, 600)
    
    def _tick(self):
        """Auto-scroll tick - ~30fps"""
        scrollbar = self.pdf_view.verticalScrollBar()
        max_val = scrollbar.maximum()
        if max_val <= 0:
            return
        
        step = int(self._speed * 3)
        if not self._is_scrolling_down:
            step = -step
        
        new_val = scrollbar.value() + step
        if new_val >= max_val:
            scrollbar.setValue(max_val)
            self._stop()
            self.osd.show_message("已到底部", QColor(255, 165, 0), 1000)
        elif new_val <= 0:
            scrollbar.setValue(0)
            self._stop()
            self.osd.show_message("已到顶部", QColor(255, 165, 0), 1000)
        else:
            scrollbar.setValue(new_val)
    
    def adjust_speed(self, delta: float):
        self._speed = max(Config.MIN_SPEED, min(Config.MAX_SPEED, self._speed + delta))
        self.toolbar.set_speed(self._speed)
        action = "加速" if delta > 0 else "减速"
        if self._is_playing:
            self.osd.show_message(f"{action}: {self._speed:.2f}x", Config.NEON_CYAN, 600)
        elif self.tabs and self.active_tab_index >= 0:
            self._start()
    
    def set_speed(self, speed: float):
        self._speed = speed
        self.toolbar.set_speed(speed)
        self.osd.show_message(f"速度 {speed:.0f}x", Config.NEON_CYAN, 600)
        if self._is_playing or (self.tabs and self.active_tab_index >= 0):
            if not self._is_playing:
                self._start()
    
    def reset_scroll(self):
        self._stop()
        self._is_scrolling_down = True
        self.toolbar.set_direction(True)
        if self.tabs and self.active_tab_index >= 0:
            sb = self.pdf_view.verticalScrollBar()
            sb.setValue(sb.maximum())
            self.osd.show_message("回到起点", Config.NEON_CYAN, 600)
    
    def toggle_direction(self):
        self._is_scrolling_down = not self._is_scrolling_down
        self.toolbar.set_direction(self._is_scrolling_down)
        direction_text = "向下滚动" if self._is_scrolling_down else "向上滚动"
        self.osd.show_message(direction_text, Config.NEON_GREEN, 800)
        
        # Scroll to appropriate end
        if self.tabs and self.active_tab_index >= 0:
            sb = self.pdf_view.verticalScrollBar()
            if self._is_scrolling_down:
                sb.setValue(sb.maximum())
            else:
                sb.setValue(0)
    
    def toggle_toolbar(self):
        visible = self.toolbar.isVisible()
        self.toolbar.setVisible(not visible)
        self.osd.show_message("工具栏已隐藏" if visible else "工具栏已显示", Config.NEON_CYAN, 600)
    
    # ===================== Events =====================
    
    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
    
    def dropEvent(self, event: QDropEvent):
        for url in event.mimeData().urls():
            fp = url.toLocalFile()
            if fp.lower().endswith('.pdf'):
                self._open_file(fp)
    
    def closeEvent(self, event):
        self._timer.stop()
        super().closeEvent(event)


# ============================================================
# Entry Point
# ============================================================
def main():
    # Enable high DPI support
    QApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )
    
    app = QApplication(sys.argv)
    app.setApplicationName("PDFScrollPlayer")
    Config.apply_dark_theme(app)
    
    window = MainWindow()
    window.show()
    
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
