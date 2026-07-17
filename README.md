# PDFScrollPlayer - PDF 自动滚动播放器

一个 macOS 桌面应用，用于自动滚动阅读 PDF 文件。

## 功能特性
- **自动滚动播放**：以可调速度自动滚动 PDF 内容
- **多页签支持**：同时打开多个 PDF，轻松切换
- **自定义快捷键**：所有操作均可自定义快捷键（⌘+,）
- **拖拽打开**：直接将 PDF 拖入窗口即可打开
- **OSD 提示**：操作时有浮动提示反馈

## 系统要求
- macOS 14.0+
- Apple Silicon (arm64)

## 构建方法
```bash
swiftc main.swift -o PDFScrollPlayer.app/Contents/MacOS/PDFScrollPlayer -framework Cocoa -framework PDFKit
codesign --force --deep --sign - PDFScrollPlayer.app
```

## 默认快捷键
| 功能 | 快捷键 |
|------|--------|
| 播放/暂停 | 空格 |
| 加速 | → |
| 减速 | ← |
| 快速加速 | ⌘+→ |
| 快速减速 | ⌘+← |
| 重置 | R |
| 切换方向 | S |
| 隐藏工具栏 | H |
