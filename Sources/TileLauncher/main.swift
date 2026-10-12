import AppKit
import SwiftUI
import ApplicationServices
import DeckCore

final class DeckPanel: NSPanel {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performClose(_ sender: Any?) { onClose?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let runningBuild: AppBuild
    private var replacementRequested = false
    init(build: AppBuild) {
        runningBuild = build
        super.init()
    }
    let settings = SettingsStore()
    let tracker = WindowTracker()
    let hold = HoldMonitor()
    let loginItem = LoginItemManager()
    let presentation = OverlayPresentation()
    let menuCatalog = MenuCatalog()
    private var visibleSnapshot: OverlaySnapshot?
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
        configureApplicationMenu()
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

        tracker.onChange = { [weak self] windows in
            guard let self else { return }
            self.windows = windows
            if self.panel?.isVisible == true {
                let states = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.desktop) })
                if self.presentation.windowDesktops != states { self.presentation.windowDesktops = states }
            }
        }
        hold.onShow = { [weak self] in self?.show(held: true) }
        hold.onHide = { [weak self] reason in
            guard let self, self.presentation.dismisses(for: reason) else { return }
            self.hide()
        }
        hold.onCancel = { [weak self] in self?.pendingAction = nil; self?.presentation.selection = nil }
        hold.onRelease = { [weak self] in
            let action = self?.pendingAction
            self?.pendingAction = nil
            self?.presentation.selection = nil
            action?()
        }
        hold.ownsKeyboard = { [weak self] in self?.panel?.isKeyWindow == true }
        hold.onShortcut = { [weak self] shortcut in
            guard let self else { return }
            switch shortcut {
            case .pin: self.presentation.pin()
            case .settings: self.openSettings()
            case .close: self.hide()
            case .number(let index, let command): self.selectNumber(index, command: command)
            }
        }
        hold.start()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(reopenNotification(_:)),
            name: InstanceCoordinator.reopenName, object: String(getuid()))
        observers.append(NotificationCenter.default.addObserver(forName: .launcherFocusChanged, object: nil, queue: .main) { [weak self] note in
            self?.settings.focusProfileID = note.userInfo?["profileID"] as? String
        })
        refreshFocus()
        updateApps()
        checkPermission(force: true)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateApps()
                self?.refreshWindows()
                self?.checkPermission()
                if name == NSWorkspace.didWakeNotification { self?.refreshFocus() }
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
            if self?.presentation.isPinned != true { self?.hide() }
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
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.async { self.openSettings() }
        }
    }

    private func configureApplicationMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Tile Launcher")
        let settingsItem = applicationMenu.addItem(withTitle: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Tile Launcher 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Tile Launcher 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "파일")
        fileMenu.addItem(withTitle: "창 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        NSApp.mainMenu = menu
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
    @objc private func reopenNotification(_ notification: Notification) {
        reopenExistingInterface(settings: notification.userInfo?["settings"] as? Bool == true, checkForUpdate: false)
    }
    private func reopenExistingInterface(settings: Bool = false, checkForUpdate: Bool = true) {
        // Finder/open may reuse this process even after the app at the same path
        // was rebuilt. Start a new instance so the normal handoff policy can run.
        if checkForUpdate, let diskBuild = try? InstanceCoordinator.build(at: Bundle.main.bundleURL),
           diskBuild != runningBuild {
            guard !replacementRequested else { return }
            replacementRequested = true
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.arguments = [settings ? "--settings" : "--show"]
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, failure in
                DispatchQueue.main.async {
                    if let failure {
                        self?.replacementRequested = false
                        self?.error("새 빌드를 열지 못했습니다. \(failure.localizedDescription)")
                    }
                }
            }
            // Permit another attempt if the replacement could not complete its startup.
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.replacementRequested = false }
            return
        }
        if settings { openSettings(); return }
        if let preferences, preferences.isVisible {
            NSApp.activate()
            preferences.makeKeyAndOrderFront(nil)
        } else { show(held: false) }
    }
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
        let snapshot = OverlaySnapshot(context: lastContext,
                                       contextWindowTitle: windows.first { $0.pid == lastContext?.pid }?.title,
                                       apps: Array(apps.prefix(3)),
                                       windows: Array(windows.prefix(count)), layout: layout, permission: trusted,
                                       pins: settings.pins, profileID: settings.activeProfile.id,
                                       profileName: settings.activeProfile.name, shortcuts: settings.numberShortcuts,
                                       commands: MenuCommand.ordered(settings.commands, appID: lastContext?.id ?? ""))
        visibleSnapshot = snapshot
        let folderBrowser = FolderBrowser()
        browser = folderBrowser
        presentation.reset()
        presentation.windowDesktops = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.desktop) })
        let view = DeckView(snapshot: snapshot, settings: settings, browser: folderBrowser, presentation: presentation,
                            selectApp: { [weak self] in self?.select(app: $0) },
                            selectPin: { [weak self] in self?.select(pin: $0) },
                            selectMenu: { [weak self] in self?.select(menu: $0, context: snapshot.context, window: snapshot.windows.first { $0.pid == snapshot.context?.pid }) },
                            changeProfile: { [weak self] id in self?.changeProfile(id) },
                            selectWindow: { [weak self] in self?.select(window: $0) },
                            openURL: { [weak self] in self?.select(url: $0) },
                            openInFinder: { [weak self] in self?.selectFolderInFinder($0) },
                            openTrash: { [weak self] in self?.selectTrash() },
                            showSettings: { [weak self] in self?.performAfterRelease { self?.openSettings() } },
                            requestPermission: { [weak self] in self?.performAfterRelease { self?.requestPermission() } },
                            dismiss: { [weak self] in
                                self?.pendingAction = nil
                                self?.hide()
                            })
        let hosting = NSHostingView(rootView: view)
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 28
        glass.contentView = hosting
        let window = DeckPanel(contentRect: layout.frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        window.onClose = { [weak self] in
            self?.pendingAction = nil
            self?.hide()
        }
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
        panel = window
        heldPresentation = held
        hold.isShowing = true
        // Receive local shortcuts without activating the launcher or changing the
        // captured app context. Global monitors cannot consume another app's keys.
        window.makeKeyAndOrderFront(nil)
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
        visibleSnapshot = nil
        browser?.close()
        browser = nil
        hold.isShowing = false
        presentation.reset()
    }
    private func performAfterRelease(_ action: @escaping () -> Void) {
        if hold.optionDown && (heldPresentation || presentation.isPinned) {
            pendingAction = action
            if !presentation.isPinned { hide() }
        } else {
            if !presentation.isPinned { hide() }
            action()
        }
    }
    private func refreshFocus(completion: (() -> Void)? = nil) {
        Task { @MainActor [weak self] in
            do { self?.settings.focusProfileID = try await LauncherFocusIntent.current.profile?.id }
            catch { self?.settings.focusProfileID = nil }
            completion?()
        }
    }
    private func changeProfile(_ id: String?) {
        pendingAction = nil
        if let id {
            settings.selectProfile(id)
            redisplayProfile()
        } else {
            settings.followFocus = true
            let originalPanel = panel
            refreshFocus { [weak self, weak originalPanel] in
                guard let self, let originalPanel, self.settings.followFocus,
                      self.panel === originalPanel, originalPanel.isVisible else { return }
                self.redisplayProfile()
            }
        }
    }
    private func redisplayProfile() {
        let pinned = presentation.isPinned
        let held = heldPresentation
        pendingAction = nil
        hide()
        show(held: held)
        if pinned { presentation.pin() }
    }
    private func selectNumber(_ index: Int, command: Bool) {
        guard let snapshot = visibleSnapshot, browser?.current == nil else { NSSound.beep(); return }
        if snapshot.shortcuts.targetsWindows(command: command) {
            guard snapshot.windows.indices.contains(index) else { NSSound.beep(); return }
            let window = snapshot.windows[index]
            presentation.selection = "window:\(window.id)"
            pendingAction = { [weak self] in self?.select(window: window) }
        } else {
            guard snapshot.pins.indices.contains(index) else { NSSound.beep(); return }
            let pin = snapshot.pins[index]
            if pin.opensInOverlay {
                select(pin: pin)
                return
            }
            presentation.selection = "pin:\(pin.id)"
            pendingAction = { [weak self] in self?.select(pin: pin) }
        }
    }
    private func select(pin: PinnedItem) {
        if pin.kind == .trash { selectTrash() }
        else if pin.kind == .app { select(url: pin.url) }
        else if pin.opensInOverlay { browser?.open(pin) }
        else { selectFolderInFinder(pin.url) }
    }
    private func select(menu: MenuCommand, context: AppItem?, window: WindowItem?) {
        guard let context else { return }
        performAfterRelease { [weak self] in
            guard let self else { return }
            guard let running = NSRunningApplication(processIdentifier: context.pid), !running.isTerminated else {
                self.error("메뉴를 사용할 앱이 종료되었습니다.")
                return
            }
            let run = { [weak self] in
                self?.menuCatalog.execute(menu, in: context) { [weak self] message in
                    if let message { self?.error(message) } else { self?.settings.recordUse(menu.id) }
                }
            }
            if let window {
                self.tracker.focus(id: window.id) { [weak self] message in
                    if let message { self?.error(message) } else { run() }
                }
            } else {
                NSApp.yieldActivation(to: running)
                if running.activate(options: []) { run() }
                else { self.error("메뉴를 사용할 앱을 활성화하지 못했습니다.") }
            }
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
        pendingAction = nil
        hide()
        if let preferences {
            NSApp.activate()
            preferences.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(settings: settings, loginItem: loginItem, preferredApp: lastContext, requestPermission: requestPermission)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Tile Launcher 설정"
        window.contentView = NSHostingView(rootView: view)
        window.minSize = NSSize(width: 540, height: 660)
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
    private func selectFolderInFinder(_ url: URL) {
        performAfterRelease { [weak self] in
            guard let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") else {
                self?.error("Finder를 찾지 못했습니다.")
                return
            }
            // Ordinary folder URLs only. Unified Trash uses a Finder object instead.
            NSWorkspace.shared.open([url], withApplicationAt: finder,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, failure in
                if let failure {
                    DispatchQueue.main.async {
                        self?.error("Finder에서 폴더를 열지 못했습니다. \(failure.localizedDescription)")
                    }
                }
            }
        }
    }
    private func selectTrash() {
        performAfterRelease { [weak self] in
            guard let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") else {
                self?.error("Finder를 찾지 못했습니다.")
                return
            }
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.appleEvent = try FinderTrashRequest.makeOpenEvent()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: finder, configuration: configuration) { _, failure in
                    if let failure {
                        DispatchQueue.main.async {
                            self?.error("Finder의 통합 휴지통을 열지 못했습니다. \(failure.localizedDescription)")
                        }
                    }
                }
            } catch { self?.error(error.localizedDescription) }
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopenExistingInterface()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        hold.stop()
        permissionTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }
}

// Register with AppKit, then acquire before constructing monitors or the status item.
let application = NSApplication.shared
let instanceLock: InstanceLock
let runningBuild: AppBuild
do {
    runningBuild = try InstanceCoordinator.build(at: Bundle.main.bundleURL)
    guard let lock = try InstanceCoordinator.acquire(build: runningBuild) else { exit(0) }
    instanceLock = lock
} catch {
    let alert = NSAlert()
    alert.messageText = "Tile Launcher를 시작하지 못했습니다."
    alert.informativeText = "중복 실행 확인에 실패했습니다. \(error.localizedDescription)"
    alert.runModal()
    exit(1)
}
let delegate = AppDelegate(build: runningBuild)
application.delegate = delegate
withExtendedLifetime(instanceLock) { application.run() }
