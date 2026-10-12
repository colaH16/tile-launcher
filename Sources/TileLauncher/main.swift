import AppKit
import SwiftUI
import ApplicationServices
import DeckCore

final class DeckPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let tracker = WindowTracker()
    let hold = HoldMonitor()
    private var appRecency = Recency<String>()
    private var apps: [AppItem] = []
    private var windows: [WindowItem] = []
    private var lastContext: AppItem?
    private var statusItem: NSStatusItem!
    private var panel: DeckPanel?
    private var preferences: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private var trusted = false
    private var pendingAction: (() -> Void)?
    private var heldPresentation = false
    private var browser: FolderBrowser?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Tile Launcher")
        let menu = NSMenu()
        menu.addItem(withTitle: "Tile Launcher 열기", action: #selector(openFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "접근성 권한 요청…", action: #selector(requestPermission), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu

        tracker.onChange = { [weak self] in self?.windows = $0 }
        hold.onShow = { [weak self] in self?.show(held: true) }
        hold.onHide = { [weak self] in self?.hide() }
        hold.onCancel = { [weak self] in self?.pendingAction = nil }
        hold.onRelease = { [weak self] in
            let action = self?.pendingAction
            self?.pendingAction = nil
            action?()
        }
        hold.start()
        updateApps()
        checkPermission(force: true)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateApps()
                self?.refreshWindows()
                self?.checkPermission()
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let item = self.item(app) else { return }
            self.appRecency.touch(item.id)
            self.lastContext = item
            self.updateApps()
            self.checkPermission()
            self.tracker.activate(item)
        })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.hide()
            self?.refreshWindows()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.hide()
        })
        // Trust can be granted in System Settings while this accessory app stays inactive.
        // This checks one Boolean; it does not poll other apps or their menus.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }
        permissionTimer?.tolerance = 1
        if CommandLine.arguments.contains("--show") || CommandLine.arguments.contains("--render-check") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.show(held: false) }
        }
    }

    private func item(_ app: NSRunningApplication) -> AppItem? {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular, !app.isTerminated else { return nil }
        return AppItem(id: app.bundleIdentifier ?? app.bundleURL?.path ?? String(app.processIdentifier),
                       pid: app.processIdentifier, name: app.localizedName ?? "앱", url: app.bundleURL)
    }
    private func updateApps() {
        let current = NSWorkspace.shared.runningApplications.compactMap(item)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let active = NSWorkspace.shared.frontmostApplication.flatMap(item) {
            if lastContext == nil { appRecency.touch(active.id) }
            lastContext = active
        }
        // Rare apps with multiple regular processes are still one recent-app tile.
        var seen = Set<String>()
        let unique = current.filter { seen.insert($0.id).inserted }
        let index = Dictionary(uniqueKeysWithValues: unique.map { ($0.id, $0) })
        appRecency.retain(Set(index.keys))
        apps = appRecency.sorted(unique.map(\.id)).compactMap { index[$0] }
    }
    private func refreshWindows() {
        let all = NSWorkspace.shared.runningApplications.compactMap(item)
        tracker.synchronize(apps: all, active: lastContext?.pid, trusted: trusted)
    }
    private func checkPermission(force: Bool = false) {
        let value = AXIsProcessTrusted()
        guard force || value != trusted else { return }
        trusted = value
        if !value { windows = [] }
        hold.start()
        refreshWindows()
    }
    @objc func requestPermission() {
        hide()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func openFromMenu() { show(held: false) }
    private func show(held: Bool) {
        guard panel?.isVisible != true else { return }
        checkPermission()
        updateApps()
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main else { return }
        let layout = PanelLayout.calculate(visibleFrame: screen.visibleFrame, cursor: point)
        guard layout.supported else {
            error("작업 영역이 너무 작습니다. 화면 배율을 조절해 주세요. 최소 패널 크기는 512 × 420pt입니다.")
            return
        }
        let count = layout.windowLimit(manual: settings.automatic ? nil : settings.manualCount, actual: windows.count)
        let snapshot = OverlaySnapshot(context: lastContext, apps: Array(apps.prefix(3)),
                                       windows: Array(windows.prefix(count)), layout: layout, permission: trusted)
        let folderBrowser = FolderBrowser()
        browser = folderBrowser
        let view = DeckView(snapshot: snapshot, settings: settings, browser: folderBrowser,
                            selectApp: { [weak self] in self?.select(app: $0) },
                            selectWindow: { [weak self] in self?.select(window: $0) },
                            openURL: { [weak self] in self?.select(url: $0) },
                            showSettings: { [weak self] in self?.performAfterRelease { self?.openSettings() } },
                            requestPermission: { [weak self] in self?.performAfterRelease { self?.requestPermission() } },
                            dismiss: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: view)
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 28
        glass.contentView = hosting
        let window = DeckPanel(contentRect: layout.frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isMovable = false
        window.contentView = glass
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: glass.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])
        window.setFrame(layout.frame, display: false)
        window.orderFrontRegardless()
        panel = window
        heldPresentation = held
        hold.isShowing = true
        if let index = CommandLine.arguments.firstIndex(of: "--render-check"),
           CommandLine.arguments.indices.contains(index + 1) {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                hosting.layoutSubtreeIfNeeded()
                if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) {
                        try? data.write(to: URL(fileURLWithPath: path))
                    }
                }
                self.quit()
            }
        }
        refreshWindows()
    }
    private func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        browser?.close()
        browser = nil
        hold.isShowing = false
    }
    private func performAfterRelease(_ action: @escaping () -> Void) {
        if heldPresentation && hold.optionDown {
            pendingAction = action
            hide()
        } else {
            hide()
            action()
        }
    }
    private func select(app: AppItem) {
        performAfterRelease { [weak self] in
            guard let running = NSRunningApplication(processIdentifier: app.pid) else {
                self?.error("앱이 종료되었습니다.")
                return
            }
            NSApp.yieldActivation(to: running)
            if !running.activate(options: []) { self?.error("앱을 활성화하지 못했습니다.") }
        }
    }
    private func select(window: WindowItem) {
        performAfterRelease { [weak self] in
            self?.tracker.focus(id: window.id) { message in
                if let message { self?.error(message) }
            }
        }
    }
    private func select(url: URL) {
        performAfterRelease { [weak self] in
            if !NSWorkspace.shared.open(url) { self?.error("항목을 열지 못했습니다. 이동되었거나 삭제되었는지 확인해 주세요.") }
        }
    }
    @objc func openSettings() {
        hide()
        if let preferences {
            NSApp.activate()
            preferences.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(settings: settings, requestPermission: requestPermission)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Tile Launcher 설정"
        window.contentView = NSHostingView(rootView: view)
        window.minSize = NSSize(width: 520, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        preferences = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
    private func error(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Tile Launcher"
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        NSApp.activate()
        alert.runModal()
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        hold.stop()
        permissionTimer?.invalidate()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
