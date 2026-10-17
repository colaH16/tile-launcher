import AppKit

// Standalone input comparison. No production imports, AX, global event monitor,
// private APIs, performDrag, or application-controlled dragging.
enum SampleMode: String, CaseIterable {
    case all = "A", margins = "E", tiles = "D"
    var title: String {
        switch self {
        case .all: return "A · 타일까지 전체 이동"
        case .margins: return "E · 섹션 뷰 분리 · 세 섹션 밖 이동"
        case .tiles: return "D · 타일 뷰 분리 · 빈자리 이동"
        }
    }
}
struct SampleElement {
    let id: String
    let label: String
    let rect: CGRect
    let color: NSColor
}
struct SampleLayout {
    let bounds: CGRect
    private(set) var elements: [SampleElement] = []
    init(bounds: CGRect) { self.bounds = bounds; elements = makeElements() }
    var menu: CGRect { CGRect(x: 24, y: 90, width: (bounds.width - 68) * 0.45, height: (bounds.height - 210) * 0.52) }
    var sessions: CGRect { CGRect(x: menu.maxX + 20, y: menu.minY, width: bounds.width - menu.maxX - 44, height: menu.height) }
    var registered: CGRect { CGRect(x: 24, y: menu.maxY + 20, width: bounds.width - 48, height: bounds.height - menu.maxY - 106) }
    var sections: [(String, CGRect)] { [("메뉴", menu), ("세션", sessions), ("등록 앱", registered)] }
    private func makeElements() -> [SampleElement] {
        var result = [SampleElement(id: "settings", label: "설정", rect: CGRect(x: bounds.width - 178, y: 20, width: 72, height: 32), color: .darkGray),
                      SampleElement(id: "pin", label: "핀", rect: CGRect(x: bounds.width - 96, y: 20, width: 72, height: 32), color: .darkGray)]
        for (section, count, columns, color) in [(0, 2, 2, NSColor.systemTeal), (1, 1, 2, NSColor.systemBlue), (2, 6, 5, NSColor.systemPurple)] {
            let (name, frame) = sections[section]
            let gap: CGFloat = 10
            let rows = 2 // Reserve empty slots to compare B section blocks with C tile-only blocks.
            let width = (frame.width - 24 - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let height = (frame.height - 46 - gap * CGFloat(rows - 1)) / CGFloat(rows)
            for index in 0..<count {
                let rect = CGRect(x: frame.minX + 12 + CGFloat(index % columns) * (width + gap),
                                  y: frame.minY + 34 + CGFloat(index / columns) * (height + gap), width: width, height: height)
                result.append(.init(id: "section\(section).tile\(index)", label: "\(name) \(index + 1)", rect: rect,
                                    color: color.blended(withFraction: 0.40, of: .darkGray) ?? color))
            }
        }
        return result
    }
    func allowsDrag(_ point: CGPoint, mode: SampleMode) -> Bool {
        guard bounds.contains(point) else { return false }
        switch mode {
        case .all: return true
        case .margins: return !sections.contains { $0.1.contains(point) }
        case .tiles: return !elements.contains { $0.rect.contains(point) }
        }
    }
    func target(_ point: CGPoint) -> String { elements.first { $0.rect.contains(point) }?.id ?? "background" }
    func label(_ point: CGPoint) -> String { elements.first { $0.rect.contains(point) }?.label ?? "배경/섹션 여백" }
}
struct PressState {
    let target: String
    let label: String
    let start: CGPoint // Screen coordinates: a moving window must not hide movement.
    let dragAllowed: Bool
    var startWindowOrigin: CGPoint?
    var displaced = false
    var windowMoved = false
    var longFired = false
    mutating func update(_ point: CGPoint) {
        if hypot(point.x - start.x, point.y - start.y) >= 6 { displaced = true }
    }
    var canLongPress: Bool { !displaced && !windowMoved && !longFired }
    var canClick: Bool { (!displaced || !dragAllowed) && !windowMoved && !longFired }
}
final class SampleLog {
    let url: URL?
    private let queue = DispatchQueue(label: "TileLauncher.DragSamples.log", qos: .utility)
    private var handle: FileHandle?
    private var bytes = 0
    private let cap = 5 * 1024 * 1024
    init(enabled: Bool = true) {
        guard enabled else { url = nil; return }
        let fm = FileManager.default
        let folder = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TileLauncherDragViewSamples")
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("drag-views-\(UUID().uuidString).jsonl")
            guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            handle = try FileHandle(forWritingTo: file); url = file
        } catch { url = nil }
    }
    func write(_ type: String, _ payload: [String: Any] = [:]) {
        var row = payload
        row["type"] = type; row["uptime"] = ProcessInfo.processInfo.systemUptime; row["unixTime"] = Date().timeIntervalSince1970
        guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        data.append(10)
        let line = data
        queue.async { [self] in
            guard bytes + line.count <= cap else { return }
            try? handle?.write(contentsOf: line); bytes += line.count
        }
    }
    func close() { queue.sync { try? handle?.synchronize(); try? handle?.close(); handle = nil } }
}
// Window movement flags remain enabled for the panel's entire lifetime.
final class SamplePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
// A fixed child responder excludes its rectangle without changing the window.
// Input classification is handled by the existing app-local monitor.
final class StationaryControlView: NSView {
    weak var canvas: SampleCanvas?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { }
    override func mouseDragged(with event: NSEvent) { }
    override func mouseUp(with event: NSEvent) { canvas?.owner?.release(event) }
    override func rightMouseDown(with event: NSEvent) { canvas?.rightMouseDown(with: event) }
}
final class SampleCanvas: NSView {
    weak var owner: SamplesController?
    var mode: SampleMode = .all
    var feedback = "타일 클릭 / 길게 누르기 / 우클릭 / 창 이동을 시험하세요."
    var counts = "클릭 0 · 길게 0 · 우클릭 0 · 실제 이동 0"
    var pinOn = false
    var activeTarget: String?
    var press: PressState?
    private var longTimer: Timer?
    var primaryButtonDown: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var cachedGeometry: SampleLayout?
    var geometry: SampleLayout {
        if cachedGeometry?.bounds != bounds { cachedGeometry = SampleLayout(bounds: bounds) }
        return cachedGeometry!
    }
    private var blockerBounds: CGRect?
    private var blockerMode: SampleMode?
    override var mouseDownCanMoveWindow: Bool { true }
    override func layout() { super.layout(); syncControlViews() }
    func syncControlViews() {
        guard blockerBounds != bounds || blockerMode != mode else { return }
        blockerBounds = bounds; blockerMode = mode
        for child in subviews where child is StationaryControlView { child.removeFromSuperview() }
        let rectangles: [CGRect]
        switch mode {
        case .all: rectangles = []
        case .margins: rectangles = geometry.sections.map { $0.1 }
        case .tiles: rectangles = geometry.elements.map { $0.rect }
        }
        for rect in rectangles {
            let child = StationaryControlView(frame: rect); child.canvas = self
            addSubview(child)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.095, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 22, yRadius: 22).fill()
        text(mode.title, rect: CGRect(x: 24, y: 20, width: bounds.width - 220, height: 30), size: 19, color: .white, bold: true)
        text(mode == .all ? "전체 영역 이동 가능 · 기존 A의 미세 움직임 처리도 그대로 비교" : mode == .margins ? "세 직사각형 안은 이동 금지 · 위/아래/좌/우/섹션 사이에서 이동" : "타일·설정·핀만 이동 금지 · 섹션 내부 빈자리와 타일 사이도 이동", rect: CGRect(x: 24, y: 58, width: bounds.width - 48, height: 24), size: 12, color: .lightGray)
        for (name, frame) in geometry.sections {
            (mode == .margins ? NSColor(calibratedWhite: 0.17, alpha: 1) : NSColor(calibratedWhite: 0.13, alpha: 1)).setFill()
            NSBezierPath(rect: frame).fill()
            (mode == .margins ? NSColor.systemOrange : .darkGray).setStroke()
            let outline = NSBezierPath(rect: frame); outline.lineWidth = 1; outline.stroke()
            text(name + (mode == .margins ? " · 영역 전체 이동 금지" : mode == .tiles ? " · 타일만 금지 / 빈칸 이동" : " · 타일도 이동 가능"), rect: frame.insetBy(dx: 12, dy: 10), size: 12, color: .lightGray)
        }
        for item in geometry.elements {
            let selected = activeTarget == item.id
            (selected ? item.color.blended(withFraction: 0.18, of: .white)! : item.color).setFill()
            NSBezierPath(roundedRect: item.rect, xRadius: 6, yRadius: 6).fill()
            let label = item.id == "pin" ? (pinOn ? "핀 ON" : "핀 OFF") : item.label
            text(label, rect: item.rect.insetBy(dx: 9, dy: max(7, (item.rect.height - 18) / 2)), size: 13, color: .white, bold: true)
        }
        text(feedback, rect: CGRect(x: 24, y: bounds.height - 69, width: bounds.width - 48, height: 27), size: 12, color: .white)
        text(counts, rect: CGRect(x: 24, y: bounds.height - 38, width: bounds.width - 48, height: 20), size: 11, color: .lightGray)
    }
    private func text(_ value: String, rect: CGRect, size: CGFloat, color: NSColor, bold: Bool = false) {
        (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: color])
    }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
    }
    override func mouseUp(with event: NSEvent) { owner?.release(event); super.mouseUp(with: event) }
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        owner?.rightClick(target: geometry.target(point), label: geometry.label(point))
        let menu = NSMenu()
        let title = NSMenuItem(title: "\(geometry.label(point)) · 우클릭 인식", action: nil, keyEquivalent: "")
        menu.addItem(title)
        let item = NSMenuItem(title: "샘플 메뉴 동작", action: #selector(SamplesController.contextAction(_:)), keyEquivalent: "")
        item.target = owner; menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    func begin(_ event: NSEvent) {
        cancel("new_press")
        let point = convert(event.locationInWindow, from: nil)
        let global = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        press = PressState(target: geometry.target(point), label: geometry.label(point), start: global, dragAllowed: geometry.allowsDrag(point, mode: mode))
        press?.startWindowOrigin = window?.frame.origin
        activeTarget = press?.target; needsDisplay = true
        owner?.record("press.begin", ["target": press!.target, "dragAllowed": press!.dragAllowed, "point": [point.x, point.y], "hitView": String(describing: type(of: hitTest(point) ?? self)), "controlViews": subviews.count])
        let timer = Timer(timeInterval: 0.55, repeats: false) { [weak self] _ in
            guard let self, var current = self.press else { return }
            guard self.primaryButtonDown() else { self.cancel("release_not_delivered"); return }
            if let origin = current.startWindowOrigin, let window = self.window, window.frame.origin != origin {
                self.markWindowMoved(); return
            }
            current.update(self.pointerLocation())
            self.press = current
            if current.canLongPress {
                self.press?.longFired = true
                self.owner?.action("long", target: current.target, label: current.label)
            }
        }
        longTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }
    func update(_ event: NSEvent) {
        guard press != nil else { return }
        press?.update(event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation)
        if press?.displaced == true { longTimer?.invalidate(); longTimer = nil }
    }
    func markWindowMoved() {
        guard press != nil else { return }
        let first = press?.windowMoved == false
        press?.windowMoved = true; longTimer?.invalidate(); longTimer = nil
        if first { activeTarget = nil; owner?.movedPress() }
    }
    func finish(_ event: NSEvent) {
        guard let previous = press else { return }
        update(event)
        if let origin = press?.startWindowOrigin, let window, window.frame.origin != origin { markWindowMoved() }
        let final = press!
        let releasePoint = convert(event.locationInWindow, from: nil)
        let sameTarget = geometry.target(releasePoint) == previous.target && bounds.contains(releasePoint)
        cancel(nil)
        if final.canClick && sameTarget { owner?.action("click", target: previous.target, label: previous.label) }
        else {
            owner?.record("press.end", ["target": final.target, "displaced": final.displaced, "windowMoved": final.windowMoved, "long": final.longFired, "sameTarget": sameTarget, "releasePoint": [releasePoint.x, releasePoint.y]])
            if final.displaced && !final.windowMoved { owner?.show(final.dragAllowed ? "움직임 입력 확인 · 실제 창 이동은 확인되지 않음" : "이 위치는 이동 금지 · 끌었으므로 클릭 취소") }
        }
    }
    func cancel(_ reason: String?) {
        longTimer?.invalidate(); longTimer = nil
        if press != nil, let reason { owner?.record("press.cancel", ["reason": reason]) }
        press = nil; activeTarget = nil; needsDisplay = true
    }
}
final class SamplesController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let log: SampleLog
    init(log: SampleLog = SampleLog()) { self.log = log; super.init() }
    var chooser: NSWindow!
    var panel: SamplePanel!
    var canvas: SampleCanvas!
    var monitor: Any?
    var counts: [String: Int] = [:]
    var lastMoveLog: TimeInterval = 0
    var mode: SampleMode = .tiles
    func applicationDidFinishLaunching(_ notification: Notification) {
        log.write("session", ["sampleVersion": "3.1-view-split-click", "os": ProcessInfo.processInfo.operatingSystemVersionString,
                              "pid": ProcessInfo.processInfo.processIdentifier, "mode": mode.rawValue, "inputScope": "own sample windows only", "maxBytes": 5242880])
        let menu = NSMenu(); let root = NSMenuItem(); menu.addItem(root)
        root.submenu = NSMenu(); root.submenu?.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let reveal = NSMenuItem(title: "로그 폴더 열기", action: #selector(revealLogs(_:)), keyEquivalent: "l")
        reveal.target = self; root.submenu?.insertItem(reveal, at: 0)
        NSApp.mainMenu = menu
        chooser = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 275), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        chooser.title = "Tile Launcher · v3 뷰 분리 시험"; chooser.delegate = self; chooser.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: "아래 A/E/D를 선택한 뒤 큰 샘플 창에서 시험하세요.\n타일·설정·핀의 클릭/길게/우클릭 결과는 창 아래에 표시됩니다. 실제 앱은 실행하지 않습니다."))
        for (index, value) in SampleMode.allCases.enumerated() {
            let button = NSButton(title: value.title, target: self, action: #selector(changeMode(_:))); button.tag = index
            stack.addArrangedSubview(button)
        }
        let end = NSButton(title: "종료 · 로그 저장", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        stack.addArrangedSubview(end)
        if let url = log.url { let label = NSTextField(labelWithString: "로그: \(url.lastPathComponent)"); label.font = .systemFont(ofSize: 10); stack.addArrangedSubview(label) }
        chooser.contentView!.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: chooser.contentView!.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: chooser.contentView!.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: chooser.contentView!.topAnchor, constant: 16)])
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel = SamplePanel(contentRect: CGRect(x: 0, y: 0, width: min(960, visible.width - 48), height: min(600, visible.height - 275)), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.isMovable = true; panel.isMovableByWindowBackground = true
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.hasShadow = false
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        canvas = SampleCanvas(frame: CGRect(origin: .zero, size: panel.frame.size)); canvas.owner = self; canvas.mode = mode
        panel.contentView = canvas
        canvas.syncControlViews()
        chooser.setFrameOrigin(CGPoint(x: visible.midX - chooser.frame.width / 2, y: visible.maxY - chooser.frame.height - 12))
        panel.setFrameOrigin(CGPoint(x: visible.midX - panel.frame.width / 2, y: max(visible.minY + 12, visible.maxY - chooser.frame.height - panel.frame.height - 32)))
        chooser.makeKeyAndOrderFront(nil); panel.orderFrontRegardless(); NSApp.activate(ignoringOtherApps: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseUp, self.canvas.press != nil { self.release(event) }
            else if event.window === self.panel {
                if event.type == .leftMouseDown { self.canvas.begin(event) }
                else if event.type == .leftMouseDragged { self.canvas.update(event) }
            }
            return event // Preserve the original event and native background handling.
        }
        record("mode.begin", ["sections": canvas.geometry.sections.map { ["name": $0.0, "rect": [$0.1.minX, $0.1.minY, $0.1.width, $0.1.height]] }])
    }
    @objc func revealLogs(_ sender: Any?) {
        if let folder = log.url?.deletingLastPathComponent() { NSWorkspace.shared.open(folder) }
    }
    @objc func changeMode(_ sender: NSButton) {
        canvas.cancel("mode_change"); mode = SampleMode.allCases[sender.tag]; canvas.mode = mode; canvas.syncControlViews()
        counts = [:]; canvas.pinOn = false; updateCounts(); show(mode.title)
        record("mode.begin")
    }
    func release(_ event: NSEvent) { canvas.finish(event) }
    func action(_ kind: String, target: String, label: String) {
        counts[kind, default: 0] += 1
        if kind == "click", target == "pin" { canvas.pinOn.toggle() }
        let name = kind == "click" ? "클릭" : "길게 누르기"
        record("action.\(kind)", ["target": target]); show("\(label) — \(name) 인식"); updateCounts()
    }
    func rightClick(target: String, label: String) {
        canvas.cancel("right_click"); counts["right", default: 0] += 1
        record("action.right", ["target": target]); show("\(label) — 우클릭 메뉴"); updateCounts()
    }
    @objc func contextAction(_ sender: NSMenuItem) { show("우클릭 메뉴의 샘플 동작 실행"); record("action.contextMenu") }
    func movedPress() { counts["move", default: 0] += 1; updateCounts(); show("실제 창 이동 감지 · 클릭은 실행하지 않음") }
    func show(_ value: String) { canvas.feedback = value; canvas.needsDisplay = true }
    func updateCounts() {
        canvas.counts = "클릭 \(counts["click", default: 0]) · 길게 \(counts["long", default: 0]) · 우클릭 \(counts["right", default: 0]) · 실제 이동 \(counts["move", default: 0])"
        canvas.needsDisplay = true
    }
    func record(_ type: String, _ data: [String: Any] = [:]) {
        var row = data; row["mode"] = mode.rawValue
        if let panel { row["backgroundMovable"] = panel.isMovableByWindowBackground; row["frame"] = [panel.frame.minX, panel.frame.minY, panel.frame.width, panel.frame.height]; row["movable"] = panel.isMovable; row["windowNumber"] = panel.windowNumber }
        log.write(type, row)
    }
    func windowDidMove(_ notification: Notification) {
        guard let moved = notification.object as? NSWindow, moved === panel, canvas != nil else { return }
        canvas.markWindowMoved()
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastMoveLog >= 0.1 { lastMoveLog = now; record("window.didMove") }
    }
    func windowWillClose(_ notification: Notification) { if notification.object as? NSWindow === chooser { NSApp.terminate(nil) } }
    func applicationWillTerminate(_ notification: Notification) {
        canvas?.cancel("shutdown")
        if let monitor { NSEvent.removeMonitor(monitor) }
        log.write("session.end"); log.close()
    }
}

func selfTest() {
    func check(_ value: @autoclosure () -> Bool, _ description: String) {
        guard value() else { fputs("FAIL: \(description)\n", stderr); exit(1) }
    }
    for size in [CGSize(width: 640, height: 450), CGSize(width: 960, height: 600), CGSize(width: 1440, height: 900)] {
        let layout = SampleLayout(bounds: CGRect(origin: .zero, size: size))
        for (_, rect) in layout.sections {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            check(layout.allowsDrag(center, mode: .all), "A blocked section")
            check(!layout.allowsDrag(center, mode: .margins), "B allowed section")
            check(layout.bounds.contains(rect), "Section outside canvas")
        }
        for point in [CGPoint(x: 4, y: size.height/2), CGPoint(x: size.width-4,y: size.height/2), CGPoint(x: size.width/2,y: 8), CGPoint(x: size.width/2,y: size.height-8), CGPoint(x: layout.menu.maxX+10,y: layout.menu.midY), CGPoint(x: size.width/2,y: layout.menu.maxY+10)] {
            check(layout.allowsDrag(point, mode: .margins), "B blocked margin/gap")
        }
        let insideBlank = CGPoint(x: layout.menu.minX + 4, y: layout.menu.minY + 4)
        check(layout.allowsDrag(insideBlank, mode: .tiles), "C blocked blank space inside section")
        check(!layout.allowsDrag(insideBlank, mode: .margins), "B allowed blank space inside section")
        for item in layout.elements where item.id.hasPrefix("section") {
            check(!layout.allowsDrag(CGPoint(x:item.rect.midX,y:item.rect.midY),mode:.margins), "B allowed tile")
            check(!layout.allowsDrag(CGPoint(x:item.rect.midX,y:item.rect.midY),mode:.tiles), "C allowed tile")
        }
    }
    var press = PressState(target: "test", label: "test", start: .zero, dragAllowed: true)
    press.update(CGPoint(x: 2, y: 2)); check(press.canClick && press.canLongPress, "Small movement lost click")
    press.update(CGPoint(x: 7, y: 0)); check(!press.canClick && !press.canLongPress, "Movement kept click/long")
    press = PressState(target: "test", label: "test", start: .zero, dragAllowed: true)
    press.longFired = true; check(!press.canClick && !press.canLongPress, "Long press duplicated click")
    press = PressState(target: "test", label: "test", start: .zero, dragAllowed: true)
    press.windowMoved = true; check(!press.canClick && !press.canLongPress, "Real movement kept click")
    press = PressState(target: "test", label: "test", start: .zero, dragAllowed: false)
    press.update(CGPoint(x: 30, y: 0)); check(press.canClick && !press.canLongPress, "Excluded tile lost click after movement")
    press.windowMoved = true; check(!press.canClick, "Moved window retained excluded click")
    print("PASS: A/E/D region policy at three sizes; section rectangles, margins/gaps, tile exclusion, jitter, drag/long/click exclusivity.")
}
if CommandLine.arguments.contains("--self-test-native") {
    _ = NSApplication.shared
    let owner = SamplesController(log: SampleLog(enabled: false))
    let panel = SamplePanel(contentRect: CGRect(x: 0, y: 0, width: 960, height: 600), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let canvas = SampleCanvas(frame: CGRect(x: 0, y: 0, width: 960, height: 600))
    panel.isReleasedWhenClosed = false; panel.isMovable = true; panel.isMovableByWindowBackground = true
    panel.contentView = canvas; canvas.owner = owner; owner.canvas = canvas; owner.panel = panel
    func check(_ condition: @autoclosure () -> Bool, line: Int = #line) { if !condition() { fputs("Native fixture failed at \(line)\n", stderr); exit(1) } }
    func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    let point = CGPoint(x: canvas.geometry.elements[2].rect.midX, y: canvas.geometry.elements[2].rect.midY)
    for mode in SampleMode.allCases {
        owner.mode = mode; canvas.mode = mode; canvas.syncControlViews()
        let previous = owner.counts["click", default: 0]
        canvas.begin(event(.leftMouseDown, point)); check(canvas.mouseDownCanMoveWindow)
        let hit = canvas.hitTest(point)!
        check((hit is StationaryControlView) == (mode != .all))
        check(hit.mouseDownCanMoveWindow == (mode == .all))
        check(canvas.hitTest(CGPoint(x: 4, y: 4)) === canvas)
        check(panel.isMovable && panel.isMovableByWindowBackground)
        canvas.finish(event(.leftMouseUp, point)); check(owner.counts["click"] == previous + 1)
        check(panel.isMovable && panel.isMovableByWindowBackground)
        canvas.finish(event(.leftMouseUp, point)); check(owner.counts["click"] == previous + 1)
        var expectedClicks = previous + 1
        canvas.begin(event(.leftMouseDown, point))
        canvas.finish(event(.leftMouseUp, CGPoint(x: point.x + 9, y: point.y)))
        if mode != .all { expectedClicks += 1 }
        check(owner.counts["click"] == expectedClicks)
        canvas.begin(event(.leftMouseDown, point))
        canvas.finish(event(.leftMouseUp, CGPoint(x: 4, y: 4)))
        check(owner.counts["click"] == expectedClicks)
        canvas.begin(event(.leftMouseDown, point)); canvas.markWindowMoved()
        canvas.finish(event(.leftMouseUp, point)); check(owner.counts["click"] == expectedClicks)
        let longBefore = owner.counts["long", default: 0]
        canvas.primaryButtonDown = { true }
        canvas.pointerLocation = { panel.convertPoint(toScreen: canvas.convert(point, to: nil)) }
        canvas.begin(event(.leftMouseDown, point))
        RunLoop.main.run(until: Date().addingTimeInterval(0.65))
        check(owner.counts["long"] == longBefore + 1)
        canvas.finish(event(.leftMouseUp, point)); check(owner.counts["click"] == expectedClicks)
        canvas.primaryButtonDown = { false }
        canvas.begin(event(.leftMouseDown, point))
        RunLoop.main.run(until: Date().addingTimeInterval(0.65))
        check(canvas.press == nil && owner.counts["long"] == longBefore + 1)
    }
    // Regression: repeated excluded input must not change either window flag,
    // replace child views during a press, or change background hit routing.
    owner.mode = .tiles; canvas.mode = .tiles; canvas.syncControlViews()
    let identities = canvas.subviews.map { ObjectIdentifier($0) }
    for _ in 0..<20 {
        for item in canvas.geometry.elements {
            let center = CGPoint(x: item.rect.midX, y: item.rect.midY)
            let child = canvas.hitTest(center) as! StationaryControlView
            canvas.begin(event(.leftMouseDown, center))
            child.mouseDown(with: event(.leftMouseDown, center))
            child.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: center.x + 12, y: center.y)))
            canvas.finish(event(.leftMouseUp, CGPoint(x: center.x + 12, y: center.y)))
            check(panel.isMovable && panel.isMovableByWindowBackground)
            check(canvas.hitTest(CGPoint(x: canvas.geometry.menu.minX + 4, y: canvas.geometry.menu.minY + 4)) === canvas)
        }
        canvas.syncControlViews()
        check(canvas.subviews.map { ObjectIdentifier($0) } == identities)
    }
    owner.rightClick(target: "test", label: "test"); check(owner.counts["right"] == 1)
    let pin = canvas.geometry.elements[1].rect
    let pinPoint = CGPoint(x: pin.midX, y: pin.midY)
    canvas.begin(event(.leftMouseDown, pinPoint)); canvas.finish(event(.leftMouseUp, pinPoint)); check(canvas.pinOn)
    canvas.cancel(nil)
    print("PASS: offscreen AppKit A/E/D constant window flags, child responder hit policy, click release/dedup, drag cancellation, real one-shot long timer, no-up cancellation, right action and pin toggle. No OS drag was invoked.")
    exit(0)
}
if CommandLine.arguments.contains("--self-test") { selfTest(); exit(0) }
if let flag = CommandLine.arguments.firstIndex(of: "--render"), flag + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for mode in SampleMode.allCases {
        let view = SampleCanvas(frame: CGRect(x:0,y:0,width:960,height:600)); view.mode = mode
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("sample-\(mode.rawValue).png"))
    }
    print("Rendered A/E/D layout only; physical dragging not tested."); exit(0)
}
let app = NSApplication.shared
let delegate = SamplesController()
app.setActivationPolicy(.regular); app.delegate = delegate; app.run()
