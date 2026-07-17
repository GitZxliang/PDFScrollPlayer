import Cocoa
import PDFKit

// MARK: - 核心配置
struct Config {
    static let barHeight: CGFloat = 56
    static let minSpeed: CGFloat = 0.1
    static let maxSpeed: CGFloat = 5.0
    static let speedStep: CGFloat = 0.1
    static let fastSpeedStep: CGFloat = 0.5
    static let scrollLineStep: CGFloat = 80
    static let scrollPagePercent: CGFloat = 0.8
    static let osdDuration: TimeInterval = 1.2

    // 科技风配色
    static let neonBlue   = NSColor(calibratedRed: 0.3, green: 0.6, blue: 1.0, alpha: 1)
    static let neonCyan   = NSColor(calibratedRed: 0.2, green: 0.85, blue: 1.0, alpha: 1)
    static let neonGreen  = NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.6, alpha: 1)
    static let neonRed    = NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.35, alpha: 1)
    static let darkBg     = NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.14, alpha: 1)
    static let cardBg     = NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.22, alpha: 1)
    static let surfaceBg  = NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.26, alpha: 1)
    static let dimText    = NSColor(calibratedWhite: 0.45, alpha: 1)
}

func findScrollView(in view: NSView, depth: Int = 0) -> NSScrollView? {
    guard depth < 100 else { return nil }
    if let sv = view as? NSScrollView { return sv }
    for sub in view.subviews {
        if let sv = findScrollView(in: sub, depth: depth + 1) { return sv }
    }
    return nil
}

// MARK: - TabCloseButton (hover-aware close button)

class PDFTab {
    let id = UUID(); let url: URL; let document: PDFDocument; let fileName: String
    var scrollPosition: CGFloat = 0; var speed: CGFloat = 1.0; var isPlaying = false
    init(url: URL) throws {
        guard let doc = PDFDocument(url: url) else {
            throw NSError(domain: "PDFScrollPlayer", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Cannot read"])
        }
        self.url = url; self.document = doc; self.fileName = url.lastPathComponent
    }
}

// ============================================================
// MARK: - Hover Components
// ============================================================
class TabCloseButton: NSButton {
    var ta: NSTrackingArea?
    override func updateTrackingAreas() {
        if let t = ta { removeTrackingArea(t) }
        ta = NSTrackingArea(rect: bounds, options: [.activeInActiveApp, .mouseEnteredAndExited], owner: self, userInfo: nil)
        if let t = ta { addTrackingArea(t) }; super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { contentTintColor = Config.neonRed.withAlphaComponent(0.9) }
    override func mouseExited(with event: NSEvent) { contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1) }
}
class HoverAddButton: NSButton {
    var ta: NSTrackingArea?
    override func updateTrackingAreas() {
        if let t = ta { removeTrackingArea(t) }
        ta = NSTrackingArea(rect: bounds, options: [.activeInActiveApp, .mouseEnteredAndExited], owner: self, userInfo: nil)
        if let t = ta { addTrackingArea(t) }; super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { contentTintColor = Config.neonCyan }
    override func mouseExited(with event: NSEvent) { contentTintColor = Config.neonCyan.withAlphaComponent(0.7) }
}
class HoverTabView: NSView {
    var isActive = false; var ta: NSTrackingArea?
    var tabIndex: Int = -1
    weak var tabDelegate: AppDelegate?
    override func updateTrackingAreas() {
        if let t = ta { removeTrackingArea(t) }
        ta = NSTrackingArea(rect: bounds, options: [.activeInActiveApp, .mouseEnteredAndExited], owner: self, userInfo: nil)
        if let t = ta { addTrackingArea(t) }; super.updateTrackingAreas()
    }
    override func mouseDown(with event: NSEvent) {
        guard tabIndex >= 0, let d = tabDelegate else { return }
        d.tabClickedAtIndex(tabIndex)
    }
    override func mouseEntered(with event: NSEvent) { guard !isActive else { return }; layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.12).cgColor }
    override func mouseExited(with event: NSEvent) { guard !isActive else { return }; layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.05).cgColor }
}

// ============================================================
// MARK: - AppDelegate
// ============================================================


// MARK: - PDFCanvas
final class PDFCanvas: NSView {
    var onDrop: ((URL) -> Void)?
    var isDragOver = false

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { isDragOver = true; needsDisplay = true; return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { isDragOver = false; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragOver = false; needsDisplay = true
        guard let url = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first, url.pathExtension.lowercased() == "pdf" else { return false }
        onDrop?(url); return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard subviews.isEmpty || isDragOver else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bgC = [Config.darkBg.cgColor, NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.24, alpha: 1).cgColor]
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgC as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: bounds.height), options: [])
        }
        if isDragOver { drawDropOverlay() } else { drawLandingContent() }
    }

    private func drawLandingContent() {}
    private func drawDropOverlay() {}
}
// ============================================================
// MARK: - OSDWindow
// ============================================================
class OSDWindow: NSWindow {
    static weak var current: OSDWindow?

    static func show(text: String, icon: String? = nil, color: NSColor = Config.neonCyan, duration: TimeInterval = 1.2) {
        DispatchQueue.main.async {
            current?.orderOut(nil)
            current = nil

            let as2 = NSMutableAttributedString()
            if let ic = icon { as2.append(NSAttributedString(string: ic + "  ", attributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: color])) }
            as2.append(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: color]))

            let ts = as2.size()
            let ws = NSSize(width: ts.width + 96 + 16, height: 70)
            guard let sf = NSScreen.main?.visibleFrame else { return }
            let o = NSPoint(x: sf.midX - ws.width / 2, y: sf.midY - 80)
            let p = OSDWindow(contentRect: NSRect(origin: o, size: ws), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.level = .floating; p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let c = NSView(frame: NSRect(origin: .zero, size: ws))
            c.wantsLayer = true; c.layer?.cornerRadius = 16; c.layer?.masksToBounds = true
            let bv = NSVisualEffectView(frame: c.bounds); bv.material = .dark; bv.blendingMode = .withinWindow; bv.state = .active
            bv.wantsLayer = true; bv.layer?.cornerRadius = 16; bv.layer?.masksToBounds = true; c.addSubview(bv)
            let b2 = NSView(frame: c.bounds); b2.wantsLayer = true; b2.layer?.cornerRadius = 16; b2.layer?.masksToBounds = true
            b2.layer?.borderWidth = 1.5; b2.layer?.borderColor = color.withAlphaComponent(0.5).cgColor; c.addSubview(b2)
            let tf = NSTextField(labelWithAttributedString: as2)
            tf.frame = NSRect(x: 48, y: (ws.height - 28) / 2, width: ts.width + 8, height: 28)
            tf.isBezeled = false; tf.drawsBackground = false; c.addSubview(tf)
            p.contentView = c; p.orderFront(nil)

            c.alphaValue = 0; c.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.85, y: 0.85))
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.2; ctx.allowsImplicitAnimation = true; c.alphaValue = 1; c.layer?.setAffineTransform(.identity) }
            current = p

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                guard let cp = current, cp == p, let cc = cp.contentView else { return }
                NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.25; ctx.allowsImplicitAnimation = true; cc.alphaValue = 0; cc.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.9, y: 0.9)) }
                    completionHandler: { if current == p { p.orderOut(nil); current = nil } }
            }
        }
    }
}

// ============================================================
// MARK: - ShortcutSetting
// ============================================================
class ShortcutSetting: NSObject {
    static let defaultsKey = "PDFShortcuts"
    static var shortcuts: [String: String] = [
        "play": "space", "faster": "right", "slower": "left",
        "fastFaster": "cmd+right", "fastSlower": "cmd+left",
        "pageUp": "up", "pageDown": "down",
        "scrollUp": "shift+up", "scrollDown": "shift+down",
        "reset": "r", "toggleUI": "h",
        "direction": "s",
        "nextTab": "option+tab", "prevTab": "option+shift+tab",
        "speed1": "1", "speed2": "2", "speed3": "3", "speed5": "5", "speed10": "0"
    ]
    static let actionLabels: [String: String] = [
        "play": "播放/暂停", "faster": "加速", "slower": "减速",
        "fastFaster": "快速加速", "fastSlower": "快速减速",
        "direction": "切换方向",
        "nextTab": "下一个页签", "prevTab": "上一个页签",
        "pageUp": "上一页", "pageDown": "下一页",
        "scrollUp": "向上滚动", "scrollDown": "向下滚动",
        "reset": "重置", "toggleUI": "切换界面",
        "speed1": "速度 1x", "speed2": "速度 2x", "speed3": "速度 3x",
        "speed5": "速度 5x", "speed10": "速度 10x"
    ]
    static func loadSettings() { guard let d = UserDefaults.standard.dictionary(forKey: defaultsKey) else { return }; for (k, v) in d { if let s = v as? String { shortcuts[k] = s } } }
    static func save() { UserDefaults.standard.set(shortcuts, forKey: defaultsKey) }
    static func displayKey(_ key: String) -> String {
        let parts = key.components(separatedBy: "+")
        return parts.map { p -> String in
            switch p {
            case "cmd": return "⌘"; case "shift": return "⇧"
            case "option": return "⌥"; case "ctrl": return "⌃"
            case "space": return "空格"; case "tab": return "Tab"
            case "left": return "←"; case "right": return "→"
            case "up": return "↑"; case "down": return "↓"
            case "pageup": return "Page↑"; case "pagedown": return "Page↓"
            case "esc": return "Esc"; case "enter": return "↵"
            default: return p.uppercased()
            }
        }.joined(separator: "")
    }
    static func showEditor() {
        DispatchQueue.main.async {
            let ww: CGFloat = 520; let wh: CGFloat = 540
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: ww, height: wh), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            win.title = "自定义快捷键"; win.backgroundColor = Config.darkBg; win.center()
            let cv = NSView(frame: NSRect(x: 0, y: 0, width: ww, height: wh))
            cv.wantsLayer = true; cv.layer?.backgroundColor = Config.darkBg.cgColor
            
            let header = NSTextField(labelWithString: "快捷键设置")
            header.frame = NSRect(x: 20, y: wh - 44, width: 300, height: 28)
            header.font = NSFont.systemFont(ofSize: 18, weight: .bold); header.textColor = Config.neonCyan
            header.isBezeled = false; header.drawsBackground = false; cv.addSubview(header)
            
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 56, width: ww, height: wh - 112))
            scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .noBorder
            scroll.autoresizingMask = [.width, .height]
            
            let sorted = actionLabels.sorted { $0.key < $1.key }
            let rh: CGFloat = 38
            let ch = NSView(frame: NSRect(x: 0, y: 0, width: ww - 20, height: CGFloat(sorted.count) * rh + 12))
            
            var yOff: CGFloat = ch.bounds.height - rh
            let infoText = NSTextField(labelWithString: "点击右侧区域然后按下新快捷键")
            infoText.frame = NSRect(x: 20, y: yOff - 30, width: 360, height: 18)
            infoText.font = NSFont.systemFont(ofSize: 11); infoText.textColor = Config.dimText
            infoText.isBezeled = false; infoText.drawsBackground = false; ch.addSubview(infoText)
            yOff -= 8
            
            for (key, label) in sorted {
                let row = NSView(frame: NSRect(x: 0, y: yOff, width: ch.bounds.width, height: rh))
                let lbl = NSTextField(labelWithString: label)
                lbl.frame = NSRect(x: 20, y: 8, width: 180, height: 22)
                lbl.font = NSFont.systemFont(ofSize: 13); lbl.textColor = NSColor(calibratedWhite: 0.85, alpha: 1)
                lbl.isBezeled = false; lbl.drawsBackground = false; row.addSubview(lbl)
                
                let kf = KeyCaptureField(frame: NSRect(x: 240, y: 6, width: 200, height: 26)) { newKey in
                    if let k = newKey { shortcuts[key] = k }
                }
                kf.wantsLayer = true; kf.layer?.cornerRadius = 6
                kf.layer?.borderWidth = 1; kf.layer?.borderColor = NSColor(calibratedWhite: 0.3, alpha: 1).cgColor
                kf.layer?.backgroundColor = Config.cardBg.cgColor
                
                let curKey = shortcuts[key] ?? ""
                let displayLbl = NSTextField(labelWithString: displayKey(curKey))
                displayLbl.frame = NSRect(x: 8, y: 3, width: 184, height: 20)
                displayLbl.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
                displayLbl.textColor = Config.neonCyan; displayLbl.isBezeled = false; displayLbl.drawsBackground = false
                displayLbl.alignment = .center; displayLbl.identifier = NSUserInterfaceItemIdentifier("display_\(key)")
                kf.addSubview(displayLbl)
                
                kf.onCapture = { newKey in
                    if let k = newKey {
                        shortcuts[key] = k
                        for sv in kf.subviews {
                            if let dl = sv as? NSTextField, sv.identifier?.rawValue == "display_\(key)" {
                                dl.stringValue = displayKey(k)
                            }
                        }
                    }
                }
                row.addSubview(kf)
                ch.addSubview(row)
                yOff -= rh
            }
            scroll.documentView = ch; cv.addSubview(scroll)
            
            let saveBtn = NSButton(title: "保存", target: ShortcutSetting.self, action: #selector(ShortcutSetting.saveShortcutsFromEditor))
            saveBtn.frame = NSRect(x: 20, y: 14, width: 80, height: 28)
            saveBtn.bezelStyle = .rounded; cv.addSubview(saveBtn)
            
            let closeBtn = NSButton(title: "关闭", target: win, action: #selector(NSWindow.close))
            closeBtn.frame = NSRect(x: 110, y: 14, width: 80, height: 28)
            closeBtn.bezelStyle = .rounded; cv.addSubview(closeBtn)
            
            let resetBtn = NSButton(title: "恢复默认", target: ShortcutSetting.self, action: #selector(ShortcutSetting.resetShortcuts))
            resetBtn.frame = NSRect(x: 200, y: 14, width: 100, height: 28)
            resetBtn.bezelStyle = .rounded; cv.addSubview(resetBtn)
            
            win.contentView = cv; win.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    @objc static func saveShortcutsFromEditor() { save() }
    @objc static func resetShortcuts() {
        // Default shortcuts
        shortcuts = defaultShortcuts
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
    private static let defaultShortcuts: [String: String] = [
            "play": "space", "faster": "right", "slower": "left",
            "fastFaster": "cmd+right", "fastSlower": "cmd+left",
            "pageUp": "up", "pageDown": "down",
            "scrollUp": "shift+up", "scrollDown": "shift+down",
            "reset": "r", "toggleUI": "h", "direction": "s",
            "nextTab": "option+tab", "prevTab": "option+shift+tab",
            "speed1": "1", "speed2": "2", "speed3": "3", "speed5": "5", "speed10": "0"
        ]
}

// ============================================================
// MARK: - KeyCaptureField
// ============================================================
class KeyCaptureField: NSView {
    var onCapture: ((String?) -> Void)?
    init(frame: NSRect, onCapture: @escaping (String?) -> Void) { self.onCapture = onCapture; super.init(frame: frame); let t = NSTrackingArea(rect: bounds, options: [.activeInActiveApp, .mouseEnteredAndExited], owner: self, userInfo: nil); addTrackingArea(t) }
    required init?(coder: NSCoder) { nil }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { layer?.borderWidth = 2; layer?.borderColor = Config.neonCyan.cgColor; return true }
    override func resignFirstResponder() -> Bool { layer?.borderWidth = 1; layer?.borderColor = Config.neonBlue.withAlphaComponent(0.3).cgColor; return true }
    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if mods.contains(.command) { parts.append("cmd") }; if mods.contains(.shift) { parts.append("shift") }
        if mods.contains(.option) { parts.append("option") }; if mods.contains(.control) { parts.append("ctrl") }
        let key: String
        switch event.keyCode {
        case 48: key = "tab"; case 49: key = "space"; case 123: key = "left"; case 124: key = "right"; case 125: key = "down"; case 126: key = "up"
        case 53: key = "esc"; case 36: key = "enter"
        default: key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        }
        guard !key.isEmpty else { return }
        onCapture?(parts.isEmpty ? key : "\(parts.joined(separator: "+"))+\(key)")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let canvas = PDFCanvas()
    let pdfView = PDFView()

    // 多页签
    var tabs: [PDFTab] = []
    var activeTabIndex: Int = -1

    var cachedScrollView: NSScrollView?
    var timer: Timer?
    var eventMonitor: Any?
    var barVisible = true
    var isScrollingDown = true

    // UI 元素
    weak var statusLabel: NSTextField!
    weak var speedLabel: NSTextField!
    weak var playButton: NSButton!
    weak var landingView: NSView?
    weak var barView: NSView!
    var tabBarView: NSView!
    weak var speedSlider: NSSlider!

    // 计算属性
    var isPlaying: Bool {
        guard activeTabIndex >= 0, activeTabIndex < tabs.count else { return false }
        return tabs[activeTabIndex].isPlaying
    }
    var speed: CGFloat {
        get {
            guard activeTabIndex >= 0, activeTabIndex < tabs.count else { return 1.0 }
            return tabs[activeTabIndex].speed
        }
        set { guard activeTabIndex >= 0, activeTabIndex < tabs.count else { return }; tabs[activeTabIndex].speed = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ShortcutSetting.loadSettings(); makeWindow(); makeMenu(); installKeyboardMonitor()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return true }
    func applicationWillTerminate(_ notification: Notification) { cleanup() }

    func makeWindow() {
        let sf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let ws = NSSize(width: min(1200, sf.width * 0.8), height: min(900, sf.height * 0.85))
        let o = NSPoint(x: sf.midX - ws.width / 2, y: sf.midY - ws.height / 2 + 40)
        window = NSWindow(contentRect: NSRect(origin: o, size: ws), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "PDFScrollPlayer"; window.delegate = self; window.minSize = NSSize(width: 700, height: 500)
        window.isReleasedWhenClosed = false; window.backgroundColor = Config.darkBg
        window.contentView?.wantsLayer = true; window.contentView?.layer?.backgroundColor = Config.darkBg.cgColor

        canvas.wantsLayer = true; canvas.registerForDraggedTypes([.fileURL])
        canvas.onDrop = { [weak self] url in self?.open(url) }
        guard let cv = window.contentView else { return }
        cv.addSubview(canvas); canvas.frame = cv.bounds; canvas.autoresizingMask = [.width, .height]
        buildToolbar(); buildLandingView()
        window.makeKeyAndOrderFront(nil); window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - 工具栏
    func buildToolbar() {
        guard let cv = window?.contentView else { return }
        let bw = cv.bounds.width
        let bar = NSView(frame: NSRect(x: 0, y: cv.bounds.height - Config.barHeight, width: bw, height: Config.barHeight))
        bar.autoresizingMask = [.width, .minYMargin]; bar.wantsLayer = true; self.barView = bar

        let blur = NSVisualEffectView(frame: bar.bounds); blur.material = .dark; blur.blendingMode = .withinWindow; blur.state = .active
        blur.autoresizingMask = [.width, .height]; bar.addSubview(blur)
        let glow = NSView(frame: NSRect(x: 0, y: 0, width: bw, height: 1))
        glow.wantsLayer = true; glow.layer?.backgroundColor = Config.neonBlue.withAlphaComponent(0.35).cgColor
        glow.autoresizingMask = [.width, .minYMargin]; bar.addSubview(glow)

        let logo = NSTextField(labelWithString: "PDFScrollPlayer")
        logo.frame = NSRect(x: 16, y: 18, width: 160, height: 22)
        logo.font = NSFont.systemFont(ofSize: 14, weight: .bold); logo.textColor = .white
        logo.isBezeled = false; logo.drawsBackground = false; bar.addSubview(logo)

        let pb = NSButton(title: "\u{25B6}", target: self, action: #selector(togglePlay))
        pb.frame = NSRect(x: 200, y: 13, width: 34, height: 30); pb.bezelStyle = .texturedRounded
        pb.font = NSFont.systemFont(ofSize: 14); pb.toolTip = "播放/暂停 (空格)"
        bar.addSubview(pb); playButton = pb

        let ss = NSSlider(value: Double(speed), minValue: 0.1, maxValue: 5, target: self, action: #selector(sliderChanged))
        ss.frame = NSRect(x: 248, y: 18, width: 120, height: 18); ss.controlSize = .small
        if #available(macOS 10.15, *) { ss.trackFillColor = Config.neonBlue }
        bar.addSubview(ss); speedSlider = ss

        let sl = NSTextField(labelWithString: "1.00x")
        sl.frame = NSRect(x: 376, y: 18, width: 64, height: 20)
        sl.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold); sl.textColor = Config.neonCyan
        sl.alignment = .center; sl.isBezeled = false; sl.drawsBackground = false
        bar.addSubview(sl); speedLabel = sl

        let slowBtn = NSButton(title: "\u{2212}", target: self, action: #selector(slowerAction))
        slowBtn.frame = NSRect(x: 448, y: 13, width: 28, height: 30); slowBtn.bezelStyle = .texturedRounded
        slowBtn.font = NSFont.systemFont(ofSize: 16, weight: .bold); slowBtn.toolTip = "减速"; bar.addSubview(slowBtn)

        let fastBtn = NSButton(title: "+", target: self, action: #selector(fasterAction))
        fastBtn.frame = NSRect(x: 480, y: 13, width: 28, height: 30); fastBtn.bezelStyle = .texturedRounded
        fastBtn.font = NSFont.systemFont(ofSize: 16, weight: .bold); fastBtn.toolTip = "加速"; bar.addSubview(fastBtn)

        let resetBtn = NSButton(title: "\u{21BA}", target: self, action: #selector(resetAction))
        resetBtn.frame = NSRect(x: 518, y: 13, width: 32, height: 30); resetBtn.bezelStyle = .texturedRounded
        resetBtn.font = NSFont.systemFont(ofSize: 16); resetBtn.toolTip = "重置 (R)"; bar.addSubview(resetBtn)

        let dirBtn = NSButton(title: "\u{2191}", target: self, action: #selector(toggleDirection))
        dirBtn.frame = NSRect(x: 556, y: 13, width: 32, height: 30); dirBtn.bezelStyle = .texturedRounded
        dirBtn.font = NSFont.systemFont(ofSize: 14, weight: .bold); dirBtn.toolTip = "方向 (S)"
        dirBtn.identifier = NSUserInterfaceItemIdentifier("dirBtn"); bar.addSubview(dirBtn)

        let st = NSTextField(labelWithString: "未打开PDF")
        st.frame = NSRect(x: bw - 340, y: 18, width: 320, height: 20); st.alignment = .right
        st.textColor = Config.dimText; st.font = NSFont.systemFont(ofSize: 12)
        st.autoresizingMask = [.minXMargin]; st.lineBreakMode = .byTruncatingMiddle
        st.isBezeled = false; st.drawsBackground = false; bar.addSubview(st); statusLabel = st

        canvas.addSubview(bar)
    }

    // MARK: - 首页
    func buildLandingView() {
        guard let cv = window?.contentView else { return }
        let tabH: CGFloat = tabs.isEmpty ? 0 : 32
        let lv = NSView(frame: NSRect(x: 0, y: 0, width: cv.bounds.width, height: cv.bounds.height - Config.barHeight - tabH))
        lv.autoresizingMask = [.width, .height]; lv.wantsLayer = true; lv.layer?.backgroundColor = .clear
        canvas.addSubview(lv); landingView = lv

        let addBtn = HoverAddButton(title: "+", target: self, action: #selector(openPDF))
        addBtn.frame = NSRect(x: lv.bounds.midX - 22, y: lv.bounds.midY - 130, width: 44, height: 44)
        addBtn.bezelStyle = NSButton.BezelStyle.shadowlessSquare; addBtn.isBordered = false
        addBtn.font = NSFont.systemFont(ofSize: 24, weight: .light)
        addBtn.contentTintColor = Config.neonCyan.withAlphaComponent(0.6)
        addBtn.wantsLayer = true; addBtn.layer?.cornerRadius = 22
        addBtn.layer?.borderWidth = 2; addBtn.layer?.borderColor = Config.neonCyan.withAlphaComponent(0.3).cgColor
        addBtn.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]; addBtn.toolTip = "添加PDF"
        lv.addSubview(addBtn)

        let dh = NSTextField(labelWithString: "Drop PDF files anywhere")
        dh.frame = NSRect(x: lv.bounds.midX - 130, y: 30, width: 260, height: 20); dh.alignment = .center
        dh.font = NSFont.systemFont(ofSize: 12); dh.textColor = Config.dimText
        dh.isBezeled = false; dh.drawsBackground = false
        dh.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]; lv.addSubview(dh)
    }

    // MARK: - 页签栏 (可滚动)
    func buildTabBarView() -> NSView {
        let tabH: CGFloat = 32
        guard let cv = window?.contentView else { return NSView(frame: .zero) }
        let bar = NSView(frame: NSRect(x: 0, y: cv.bounds.height - Config.barHeight - tabH, width: cv.bounds.width, height: tabH))
        bar.autoresizingMask = [.width, .minYMargin]; bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.3).cgColor

        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: bar.bounds.width - 44, height: tabH))
        sv.autoresizingMask = [.width, .height]; sv.hasHorizontalScroller = false; sv.hasVerticalScroller = false
        sv.horizontalScrollElasticity = .none; sv.verticalScrollElasticity = .none; sv.drawsBackground = false

        let doc = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: tabH))
        var xOff: CGFloat = 8
        for (i, tab) in tabs.enumerated() {
            let name = (tab.fileName as NSString).deletingPathExtension
            let dn = name.count > 20 ? String(name.prefix(18)) + "..." : name
            let bw = CGFloat(min(max(dn.count * 9 + 40, 80), 200))
            let tv = HoverTabView(frame: NSRect(x: xOff, y: (tabH - 26) / 2, width: bw, height: 26))
            tv.wantsLayer = true; tv.layer?.cornerRadius = 6; tv.isActive = (i == activeTabIndex)
            tv.tabIndex = i; tv.tabDelegate = self

            if i == activeTabIndex {
                tv.layer?.backgroundColor = Config.neonBlue.withAlphaComponent(0.25).cgColor
                tv.layer?.borderWidth = 1; tv.layer?.borderColor = Config.neonBlue.withAlphaComponent(0.5).cgColor
                let ab = NSView(frame: NSRect(x: 4, y: 0, width: bw - 8, height: 3))
                ab.wantsLayer = true; ab.layer?.cornerRadius = 1.5; ab.layer?.backgroundColor = Config.neonCyan.cgColor
                ab.identifier = NSUserInterfaceItemIdentifier("accentBar"); tv.addSubview(ab)
            } else {
                tv.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.05).cgColor
                tv.layer?.borderWidth = 0.5; tv.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.1).cgColor
            }

            // 右键菜单
            let menu = NSMenu(title: "Tab")
            let ci = NSMenuItem(title: "关闭页签", action: #selector(menuCloseCurrentTab(_:)), keyEquivalent: "")
            ci.representedObject = i; ci.target = self; menu.addItem(ci)
            let co = NSMenuItem(title: "关闭其他页签", action: #selector(menuCloseOtherTabs(_:)), keyEquivalent: "")
            co.representedObject = i; co.target = self; menu.addItem(co)
            let ca = NSMenuItem(title: "关闭所有页签", action: #selector(menuCloseAllTabs(_:)), keyEquivalent: "")
            ca.representedObject = i; ca.target = self; menu.addItem(ca)
            tv.menu = menu

            let cb = NSButton(frame: tv.bounds); cb.title = ""
            cb.bezelStyle = NSButton.BezelStyle.shadowlessSquare; cb.isBordered = false
            cb.target = self; cb.action = #selector(tabClicked(_:)); cb.tag = i; tv.addSubview(cb)
            let lb = NSTextField(labelWithString: dn)
            lb.frame = NSRect(x: 6, y: 4, width: bw - 32, height: 18)
            lb.font = NSFont.systemFont(ofSize: 11, weight: i == activeTabIndex ? .semibold : .regular)
            lb.textColor = i == activeTabIndex ? Config.neonCyan : NSColor(calibratedWhite: 0.7, alpha: 1)
            lb.isBezeled = false; lb.drawsBackground = false; lb.lineBreakMode = .byTruncatingTail; tv.addSubview(lb)
            let xb = TabCloseButton(title: "\u{00D7}", target: self, action: #selector(closeTabClicked(_:)))
            xb.frame = NSRect(x: bw - 26, y: 2, width: 24, height: 22); xb.bezelStyle = NSButton.BezelStyle.shadowlessSquare
            xb.isBordered = false; xb.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            xb.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1); xb.tag = i; xb.toolTip = "关闭"; tv.addSubview(xb)

            doc.addSubview(tv); xOff += bw + 6
        }
        doc.frame = NSRect(x: 0, y: 0, width: xOff + 8, height: tabH); sv.documentView = doc; bar.addSubview(sv)

        let ab2 = NSButton(title: "+", target: self, action: #selector(openPDF))
        ab2.frame = NSRect(x: bar.bounds.width - 40, y: (tabH - 22) / 2, width: 36, height: 22)
        ab2.bezelStyle = NSButton.BezelStyle.shadowlessSquare; ab2.isBordered = false
        ab2.font = NSFont.systemFont(ofSize: 16, weight: .bold); ab2.contentTintColor = Config.neonCyan.withAlphaComponent(0.7)
        ab2.autoresizingMask = [.minXMargin, .minYMargin]; ab2.toolTip = "添加PDF"; bar.addSubview(ab2)
        return bar
    }

    func updateTabBarSelection() {
        guard let bar = tabBarView else { return }
        for sub in bar.subviews {
            guard let tv = sub as? HoverTabView else { continue }
            var ti = -1
            for inn in tv.subviews { if let b = inn as? NSButton, b.action == #selector(tabClicked(_:)) { ti = b.tag; break } }
            guard ti >= 0 else { continue }; let act = (ti == activeTabIndex); tv.isActive = act
            if act {
                tv.layer?.backgroundColor = Config.neonBlue.withAlphaComponent(0.25).cgColor
                tv.layer?.borderWidth = 1; tv.layer?.borderColor = Config.neonBlue.withAlphaComponent(0.5).cgColor
            } else {
                tv.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.05).cgColor
                tv.layer?.borderWidth = 0.5; tv.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.1).cgColor
            }
            for inn in tv.subviews {
                if inn.identifier?.rawValue == "accentBar" { inn.isHidden = !act }
                if let lb = inn as? NSTextField {
                    if !(inn is TabCloseButton) && !(inn is NSButton) {
                        lb.font = NSFont.systemFont(ofSize: 11, weight: act ? .semibold : .regular)
                        lb.textColor = act ? Config.neonCyan : NSColor(calibratedWhite: 0.7, alpha: 1)
                    }
                }
            }
        }
    }

    // MARK: - 页签操作
    func tabClickedAtIndex(_ idx: Int) {
        guard idx >= 0, idx < tabs.count, idx != activeTabIndex else { return }
        switchToTab(idx)
    }
    @objc func tabClicked(_ sender: NSButton) {
        tabClickedAtIndex(sender.tag)
    }
    @objc func closeTabClicked(_ sender: NSButton) { closeTab(at: sender.tag) }
    @objc func nextTab() {
        guard tabs.count > 1, activeTabIndex >= 0 else { return }
        switchToTab((activeTabIndex + 1) % tabs.count)
    }
    @objc func prevTab() {
        guard tabs.count > 1, activeTabIndex >= 0 else { return }
        switchToTab((activeTabIndex - 1 + tabs.count) % tabs.count)
    }

    func switchToTab(_ idx: Int) {
        guard idx >= 0, idx < tabs.count, idx != activeTabIndex else { return }
        saveCurrentTabState(); stop()
        activeTabIndex = idx
        let tab = tabs[idx]

        // 立即更新页签栏（视觉反馈）
        tabBarView?.removeFromSuperview(); tabBarView = buildTabBarView(); canvas.addSubview(tabBarView)

        // 下一 runloop 切换文档（让页签绘制完成后再做重活）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            pdfView.alphaValue = 0.0
            pdfView.document = tab.document
            pdfView.displayMode = .singlePageContinuous
            pdfView.displayDirection = .vertical
            pdfView.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.18, alpha: 1)
            pdfView.pageShadowsEnabled = false

            landingView?.removeFromSuperview(); landingView = nil; pdfView.removeFromSuperview()
            let tabH: CGFloat = 32
            guard let cv = window?.contentView else { return }
            pdfView.frame = NSRect(x: 0, y: 0, width: cv.bounds.width, height: cv.bounds.height - Config.barHeight - tabH)
            pdfView.autoresizingMask = [.width, .height]
            if let first = canvas.subviews.first { canvas.addSubview(pdfView, positioned: .below, relativeTo: first) }
            else { canvas.addSubview(pdfView) }
            speed = tab.speed; isScrollingDown = true; updateSpeed(); updateDirectionButton()
            statusLabel?.stringValue = "\(tab.fileName)  \(tab.document.pageCount)页"
            window?.title = "\(tab.fileName) - PDF滚动播放器"

            // 布局 + 恢复位置 + 淡入
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.pdfView.autoScales = true
                self.cachedScrollView = findScrollView(in: self.pdfView)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let sv = self.cachedScrollView {
                        let pos = tab.scrollPosition
                        if pos > 0 { sv.contentView.setBoundsOrigin(NSPoint(x: 0, y: pos)); sv.reflectScrolledClipView(sv.contentView) }
                        else { sv.contentView.setBoundsOrigin(.zero); sv.reflectScrolledClipView(sv.contentView) }
                    }
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.12; self.pdfView.animator().alphaValue = 1.0
                    }
                    if tab.isPlaying { self.start() }
                }
            }
        }
    }
    func closeTab(at idx: Int) {
        guard idx >= 0, idx < tabs.count else { return }
        stop(); tabs.remove(at: idx)
        if tabs.isEmpty {
            activeTabIndex = -1; pdfView.document = nil; pdfView.removeFromSuperview(); cachedScrollView = nil
            statusLabel?.stringValue = "未打开PDF"; window?.title = "PDF滚动播放器"; speed = 1.0; updateSpeed()
            tabBarView?.removeFromSuperview(); tabBarView = NSView(frame: .zero); buildLandingView(); canvas.needsDisplay = true
        } else {
            if idx <= activeTabIndex { activeTabIndex = max(0, activeTabIndex - 1) }
            tabBarView?.removeFromSuperview(); tabBarView = buildTabBarView(); canvas.addSubview(tabBarView)
            switchToTab(activeTabIndex)
        }
    }

    func saveCurrentTabState() {
        guard activeTabIndex >= 0, activeTabIndex < tabs.count else { return }
        let tab = tabs[activeTabIndex]; tab.speed = speed; tab.isPlaying = isPlaying
        if let sv = cachedScrollView { tab.scrollPosition = sv.contentView.bounds.origin.y }
    }

    // MARK: - 右键菜单
    @objc func menuCloseCurrentTab(_ sender: NSMenuItem) {
        guard let idx = sender.representedObject as? Int else { return }; closeTab(at: idx)
    }
    @objc func menuCloseOtherTabs(_ sender: NSMenuItem) {
        guard let ki = sender.representedObject as? Int, ki >= 0, ki < tabs.count else { return }
        stop(); cachedScrollView = nil; let keep = tabs[ki]; tabs = [keep]; activeTabIndex = 0
        tabBarView?.removeFromSuperview(); tabBarView = buildTabBarView(); canvas.addSubview(tabBarView)
        switchToTab(0)
    }
    @objc func menuCloseAllTabs(_ sender: Any) {
        stop(); cachedScrollView = nil; tabs.removeAll(); activeTabIndex = -1
        pdfView.document = nil; pdfView.removeFromSuperview()
        tabBarView?.removeFromSuperview(); tabBarView = NSView(frame: .zero)
        speed = 1.0; updateSpeed(); statusLabel?.stringValue = "未打开PDF"; window?.title = "PDF滚动播放器"
        buildLandingView(); canvas.needsDisplay = true
    }

    // MARK: - PDF 打开
    @objc func openPDF() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.allowedFileTypes = ["pdf"]; panel.allowsMultipleSelection = true
        panel.message = "Select PDF(s)"
        panel.begin { [weak self] resp in
            guard let self = self, resp == .OK else { return }
            for url in panel.urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) { self.open(url) }
        }
    }

    func open(_ url: URL) {
        do {
            let tab = try PDFTab(url: url); tabs.append(tab)
            switchToTab(tabs.count - 1)
            tabBarView?.removeFromSuperview(); tabBarView = buildTabBarView(); canvas.addSubview(tabBarView)
            OSDWindow.show(text: "已加载 \(tab.document.pageCount) 页", icon: "\u{1F4C4}", color: Config.neonGreen, duration: 1.0)
        } catch {
            OSDWindow.show(text: error.localizedDescription, icon: "\u{26A0}\u{FE0F}", color: Config.neonRed, duration: 2.0)
        }
    }

    @objc func closePDF() { guard activeTabIndex >= 0 else { return }; closeTab(at: activeTabIndex) }

    // MARK: - 播放控制
    @objc func togglePlay() {
        guard pdfView.document != nil else { OSDWindow.show(text: "请先打开PDF", icon: "\u{1F4C4}", color: .systemOrange, duration: 1.0); return }
        isPlaying ? stop() : start()
    }
    func start() {
        guard pdfView.document != nil, activeTabIndex >= 0, activeTabIndex < tabs.count else { return }
        tabs[activeTabIndex].isPlaying = true; playButton?.title = "\u{23F8}"
        timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        OSDWindow.show(text: "播放中", icon: "\u{25B6}\u{FE0F}", color: Config.neonGreen, duration: 0.6)
    }
    func stop() {
        if activeTabIndex >= 0, activeTabIndex < tabs.count { tabs[activeTabIndex].isPlaying = false; saveCurrentTabState() }
        playButton?.title = "\u{25B6}"; timer?.invalidate(); timer = nil
        if pdfView.document != nil { OSDWindow.show(text: "已暂停", icon: "\u{23F8}", color: Config.neonCyan, duration: 0.6) }
    }
    func tick() {
        guard let sv = cachedScrollView ?? findScrollView(in: pdfView), let dv = sv.documentView else {
            cachedScrollView = findScrollView(in: pdfView); return
        }
        let docH = dv.bounds.height; let clipH = sv.contentView.bounds.height; let maxY = max(0, docH - clipH)
        let dir: CGFloat = isScrollingDown ? -1.0 : 1.0
        var p = sv.contentView.bounds.origin; p.y += speed * 3.0 * dir
        if p.y >= maxY { p.y = maxY; sv.contentView.setBoundsOrigin(p); sv.reflectScrolledClipView(sv.contentView); stop(); OSDWindow.show(text: "已到底部", icon: "\u{1F3C1}", color: .systemOrange, duration: 1.0); return }
        if p.y <= 0 { p.y = 0; sv.contentView.setBoundsOrigin(p); sv.reflectScrolledClipView(sv.contentView); stop(); OSDWindow.show(text: "已到顶部", icon: "\u{1F3C1}", color: .systemOrange, duration: 1.0); return }
        sv.contentView.setBoundsOrigin(p); sv.reflectScrolledClipView(sv.contentView)
    }

    // MARK: - 速度控制
    @objc func fasterAction() { speed = min(Config.maxSpeed, speed + Config.speedStep); updateSpeed(); OSDWindow.show(text: String(format: "速度 %.2fx", speed), icon: "\u{26A1}", color: Config.neonBlue); if !isPlaying, pdfView.document != nil { start() } }
    @objc func slowerAction() { speed = max(Config.minSpeed, speed - Config.speedStep); updateSpeed(); OSDWindow.show(text: String(format: "速度 %.2fx", speed), icon: "\u{1F422}", color: Config.neonCyan) }
    @objc func fastFaster() { speed = min(Config.maxSpeed, speed + Config.fastSpeedStep); updateSpeed(); if !isPlaying, pdfView.document != nil { start() } }
    @objc func fastSlower() { speed = max(Config.minSpeed, speed - Config.fastSpeedStep); updateSpeed() }
    @objc func sliderChanged() { speed = CGFloat(speedSlider?.doubleValue ?? 1.0); updateSpeed() }
    func updateSpeed() { speedLabel?.stringValue = String(format: "%.2fx", speed); speedSlider?.doubleValue = Double(speed) }
    @objc func resetAction() { stop(); isScrollingDown = true; updateDirectionButton(); guard let sv = cachedScrollView ?? findScrollView(in: pdfView), let dv = sv.documentView else { return }; let ch = sv.contentView.bounds.height; let my = max(0, dv.bounds.height - ch); sv.contentView.setBoundsOrigin(NSPoint(x: 0, y: my)); sv.reflectScrolledClipView(sv.contentView); playButton?.title = "\u{25B6}"; OSDWindow.show(text: "回到起点", icon: "\u{21BA}", color: Config.neonCyan, duration: 0.6) }
    @objc func setSpeed1() { applySpeed(1, icon: "1\u{FE0F}\u{20E3}") }
    @objc func setSpeed2() { applySpeed(2, icon: "2\u{FE0F}\u{20E3}") }
    @objc func setSpeed3() { applySpeed(3, icon: "3\u{FE0F}\u{20E3}") }
    @objc func setSpeed5() { applySpeed(5, icon: "\u{26A1}") }
    @objc func setSpeed10() { applySpeed(10, icon: "\u{1F680}") }
    private func applySpeed(_ s: CGFloat, icon: String) { speed = s; updateSpeed(); OSDWindow.show(text: String(format: "速度 %.0fx", speed), icon: icon, color: Config.neonCyan); if !isPlaying, pdfView.document != nil { start() } }

    // MARK: - 方向
    @objc func toggleDirection() {
        isScrollingDown.toggle(); updateDirectionButton()
        let dt = isScrollingDown ? "向上滚动 \u{2191}" : "向下滚动 \u{2193}"
        OSDWindow.show(text: dt, icon: isScrollingDown ? "\u{2B06}\u{FE0F}" : "\u{2B07}\u{FE0F}", color: Config.neonGreen, duration: 0.8)
        if pdfView.document != nil { if isScrollingDown { scrollToBottom() } else { scrollToTop() } }
    }
    private func updateDirectionButton() {
        guard let bar = barView else { return }
        for sub in bar.subviews { if let b = sub as? NSButton, b.identifier?.rawValue == "dirBtn" { b.title = isScrollingDown ? "\u{2191}" : "\u{2193}"; break } }
    }
    private func scrollToTop() { guard let sv = cachedScrollView ?? findScrollView(in: pdfView) else { return }; sv.contentView.setBoundsOrigin(.zero); sv.reflectScrolledClipView(sv.contentView) }
    private func scrollToBottom() { guard let sv = cachedScrollView ?? findScrollView(in: pdfView), let dv = sv.documentView else { return }; let ch = sv.contentView.bounds.height; let my = max(0, dv.bounds.height - ch); sv.contentView.setBoundsOrigin(NSPoint(x: 0, y: my)); sv.reflectScrolledClipView(sv.contentView) }

    // MARK: - UI 切换
    @objc func toggleBar() { barVisible = !barVisible; barView?.isHidden = !barVisible; OSDWindow.show(text: barVisible ? "工具栏已显示" : "工具栏已隐藏", color: Config.neonCyan, duration: 0.6) }

    // MARK: - 键盘事件
    func installKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self else { return e }; let raw = self.rawKeyName(e)
            if e.charactersIgnoringModifiers == "o", e.modifierFlags.contains(.command) { self.openPDF(); return nil }
            if e.charactersIgnoringModifiers == "w", e.modifierFlags.contains(.command) { self.closePDF(); return nil }
            if e.charactersIgnoringModifiers == ",", e.modifierFlags.contains(.command) { ShortcutSetting.showEditor(); return nil }
            if self.match("play", raw) { self.togglePlay(); return nil }
            if self.match("faster", raw) { self.fasterAction(); return nil }
            if self.match("slower", raw) { self.slowerAction(); return nil }
            if self.match("fastFaster", raw) { self.fastFaster(); return nil }
            if self.match("fastSlower", raw) { self.fastSlower(); return nil }
            if self.match("pageUp", raw) { self.safeScrollBy(-(self.cachedScrollView?.bounds.height ?? 800) * Config.scrollPagePercent); return nil }
            if self.match("pageDown", raw) { self.safeScrollBy((self.cachedScrollView?.bounds.height ?? 800) * Config.scrollPagePercent); return nil }
            if self.match("scrollUp", raw) { self.safeScrollBy(-Config.scrollLineStep); return nil }
            if self.match("scrollDown", raw) { self.safeScrollBy(Config.scrollLineStep); return nil }
            if self.match("reset", raw) { self.resetAction(); return nil }
            if self.match("toggleUI", raw) { self.toggleBar(); return nil }
            if self.match("direction", raw) { self.toggleDirection(); return nil }
            if self.match("speed1", raw) { self.setSpeed1(); return nil }
            if self.match("speed2", raw) { self.setSpeed2(); return nil }
            if self.match("speed3", raw) { self.setSpeed3(); return nil }
            if self.match("speed5", raw) { self.setSpeed5(); return nil }
            if self.match("speed10", raw) { self.setSpeed10(); return nil }
            if self.match("nextTab", raw) { self.nextTab(); return nil }
            if self.match("prevTab", raw) { self.prevTab(); return nil }
            return e
        }
    }
    private func safeScrollBy(_ dy: CGFloat) {
        guard let sv = cachedScrollView ?? findScrollView(in: pdfView) else { return }
        let dh = sv.documentView?.bounds.height ?? 0; let ch = sv.contentView.bounds.height; let my = max(0, dh - ch)
        var p = sv.contentView.bounds.origin; p.y = max(0, min(my, p.y + dy))
        sv.contentView.setBoundsOrigin(p); sv.reflectScrolledClipView(sv.contentView)
    }
    private func rawKeyName(_ e: NSEvent) -> String {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if mods.contains(.command) { parts.append("cmd") }; if mods.contains(.shift) { parts.append("shift") }
        if mods.contains(.option) { parts.append("option") }; if mods.contains(.control) { parts.append("ctrl") }
        let key: String
        switch e.keyCode {
        case 48: key = "tab"; case 49: key = "space"; case 123: key = "left"; case 124: key = "right"
        case 125: key = "down"; case 126: key = "up"; case 116: key = "pageup"; case 121: key = "pagedown"
        default: key = e.charactersIgnoringModifiers?.lowercased() ?? ""
        }
        guard !key.isEmpty else { return "" }
        return parts.isEmpty ? key : "\(parts.joined(separator: "+"))+\(key)"
    }
    private func match(_ action: String, _ raw: String) -> Bool { ShortcutSetting.shortcuts[action] == raw }

    // MARK: - 菜单
    func makeMenu() {
        let main = NSMenu(title: "PDFScrollPlayer")
        let appItem = NSMenuItem(); appItem.submenu = NSMenu(title: "App")
        appItem.submenu?.items = [
            NSMenuItem(title: "关于", action: #selector(showAbout), keyEquivalent: ""),
            NSMenuItem.separator(),
            NSMenuItem(title: "快捷键...", action: #selector(showPrefs), keyEquivalent: ","),
            NSMenuItem.separator(),
            NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        ]
        let fileItem = NSMenuItem(); fileItem.submenu = NSMenu(title: "文件")
        fileItem.submenu?.items = [
            NSMenuItem(title: "打开PDF...", action: #selector(openPDF), keyEquivalent: "o"),
            NSMenuItem(title: "关闭PDF", action: #selector(closePDF), keyEquivalent: "w")
        ]
        let playItem = NSMenuItem(); playItem.submenu = NSMenu(title: "播放")
        if let pm = playItem.submenu {
            pm.addItem(withTitle: "播放/暂停", action: #selector(togglePlay), keyEquivalent: " ")
            pm.addItem(withTitle: "加速", action: #selector(fasterAction), keyEquivalent: "")
            pm.addItem(withTitle: "减速", action: #selector(slowerAction), keyEquivalent: "")
        }
        main.items = [appItem, fileItem, playItem]
        NSApplication.shared.mainMenu = main
    }
    @objc func showPrefs() { ShortcutSetting.showEditor() }
    @objc func showAbout() { let a = NSAlert(); a.messageText = "PDFScrollPlayer"; a.informativeText = "版本 2.0\\nPDF自动滚动阅读器，支持多页签。"; a.runModal() }

    func windowWillClose(_ notification: Notification) { cleanup() }
    private func cleanup() {
        stop(); if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        timer?.invalidate(); timer = nil; cachedScrollView = nil; tabs.removeAll(); activeTabIndex = -1; pdfView.document = nil
    }
}


let appDelegate_ = AppDelegate()
NSApplication.shared.delegate = appDelegate_
NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
