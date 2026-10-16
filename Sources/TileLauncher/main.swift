import AppKit
import SwiftUI
import ApplicationServices
import DeckCore

final class DeckPanel: NSPanel {
    var onClose: (() -> Void)?
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performClose(_ sender: Any?) { onClose?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isKeyWindow, onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let runningBuild: AppBuild
    private lazy var replacement = BuildReplacement(running: runningBuild)
    init(build: AppBuild, settings: SettingsStore = SettingsStore()) {
        runningBuild = build
        self.settings = settings
        super.init()
        _ = AppIdentity.versionLabel
    }
    let settings: SettingsStore
    private let settingsNavigation = SettingsNavigation()
    let tracker = WindowTracker()
    let hold = HoldMonitor()
    let loginItem = LoginItemManager()
    let presentation = OverlayPresentation()
    private let launches = ApplicationLaunchMonitor()
    let menuCatalog = MenuCatalog()
    private let dockHandoff = DockHandoff()
    private let appSettingsMenu = ApplicationSettingsMenu()
    private lazy var menuUsage = MenuUsageMonitor(settings: settings)
    private var menuIcons: MenuIconService?
    private var iconReadAhead: IconReadAhead?
    private var visibleContent: OverlayContent?
    private var visibleSnapshot: OverlaySnapshot? { visibleContent?.snapshot }
    private var overlayRefresh: DispatchWorkItem?
    private var appRecency = Recency<String>()
    private var apps: [AppItem] = []
    private var windows: [WindowItem] = []
    private var lastContext: AppItem?
    private var statusItem: NSStatusItem!
    private var panel: DeckPanel?
    private var preferences: NSWindow?
    private var preferencesEditor: SettingsEditingSession?
    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private var trusted = false
    private var pendingAction: (() -> Void)?
    private var keyboardFeedbackCleanup: DispatchWorkItem?
    private var heldPresentation = false
    private var optionReopen = OptionReopenMemory<PanelLayout>()
    private var browser: FolderBrowser?
    private var scrollMonitor: Any?
    private var profileScroll = ProfileScrollGesture()
    private var profileChangeRevision = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        iconReadAhead = IconReadAhead(settings: settings)
        menuIcons = MenuIconService(settings: settings)
        menuIcons?.onImagesUpdated = { [weak self] appID in self?.iconReadAhead?.prepareMenus(appID: appID) }
        NSApp.setActivationPolicy(.accessory)
        configureApplicationMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = BrandMark.menuBarImage()
        statusItem.button?.toolTip = AppIdentity.name
        let menu = NSMenu()
        menu.addItem(withTitle: "\(AppIdentity.name) 열기", action: #selector(openFromMenu), keyEquivalent: "")
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
            self.scheduleOverlayRefresh()
        }
        hold.onShow = { [weak self] in self?.show(held: true) }
        hold.onPrepare = { [weak self] in
            // Begin a background Dock read during the hold wait. Slow reads are
            // shared with visible monitoring instead of queued again at show.
            self?.dockHandoff.refresh()
            self?.prepareOverlay()
        }
        dockHandoff.onChange = { [weak self] _ in
            guard let self, self.panel?.isVisible == true else { return }
            self.scheduleOverlayRefresh()
        }
        appSettingsMenu.onChange = { [weak self] in self?.scheduleOverlayRefresh() }
        settings.onAppSettingsVisibilityChanged = { [weak self] enabled in
            guard let self else { return }
            if enabled { self.refreshAppSettingsMenu() }
            else { self.appSettingsMenu.cancel() }
            self.scheduleOverlayRefresh()
        }
        hold.onAbandon = { [weak self] in
            guard let self else { return }
            self.discardPreparedOverlay()
            if self.panel?.isVisible != true {
                self.dockHandoff.stopMonitoring()
            }
        }
        hold.onQuickReopen = { [weak self] time in
            guard let self, let layout = self.optionReopen.take(at: time, enabled: self.settings.optionReopen.enabled) else { return false }
            self.show(held: true, restoring: layout)
            return true
        }
        hold.onReopenCancelled = { [weak self] in self?.optionReopen.cancel() }
        hold.onHide = { [weak self] reason, time in
            guard let self, self.presentation.dismisses(for: reason) else { return }
            self.hide(reason: reason, at: time)
        }
        hold.onCancel = { [weak self] in
            self?.pendingAction = nil
            self?.presentation.selection = nil
            self?.clearKeyboardFeedback()
        }
        hold.onRelease = { [weak self] in
            self?.finishOptionSelection()
        }
        hold.canTriggerHold = { [weak self] in self?.settings.optionTriggerEnabled == true }
        hold.ownsKeyboard = { [weak self] in self?.panel?.isKeyWindow == true }
        hold.onShortcut = { [weak self] shortcut in
            guard let self else { return }
            switch shortcut {
            case .pin: self.pinOverlay()
            case .settings: self.openSettings()
            case .close: self.hide()
            case .profile(let step): self.cycleProfile(step)
            case .number(let index, let command): self.selectNumber(index, command: command)
            }
        }
        hold.start()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible, event.window === panel,
                  self.settings.profiles.count > 1 else { return event }
            let result = self.profileScroll.scroll(x: Double(event.scrollingDeltaX), y: Double(event.scrollingDeltaY),
                precise: event.hasPreciseScrollingDeltas, inverted: event.isDirectionInvertedFromDevice,
                time: event.timestamp, began: event.phase.contains(.began),
                ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                phased: !event.phase.isEmpty, momentum: !event.momentumPhase.isEmpty,
                cancelled: event.phase.contains(.cancelled))
            if let step = result.step { self.cycleProfile(step) }
            return result.consume ? nil : event
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(reopenNotification(_:)),
            name: InstanceCoordinator.reopenName, object: String(getuid()))
        observers.append(NotificationCenter.default.addObserver(forName: .launcherFocusChanged, object: nil, queue: .main) { [weak self] note in
            self?.settings.focusProfileID = note.userInfo?["profileID"] as? String
        })
        refreshFocus()
        updateApps()
        menuUsage.onCapture = { [weak self] in self?.scheduleOverlayRefresh() }
        menuUsage.start()
        checkPermission(force: true)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if name == NSWorkspace.didTerminateApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.appSettingsMenu.invalidate(pid: app.processIdentifier)
                }
                if name == NSWorkspace.didLaunchApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   let url = self?.item(app)?.url { self?.iconReadAhead?.prepareApp(url) }
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
            self.iconReadAhead?.activate(item)
            self.refreshAppSettingsMenu()
            self.scheduleOverlayRefresh()
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
        updateApps()
        if let lastContext { iconReadAhead?.activate(lastContext) }
        refreshAppSettingsMenu()
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
        let applicationMenu = NSMenu(title: AppIdentity.name)
        let settingsItem = applicationMenu.addItem(withTitle: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "\(AppIdentity.name) 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "\(AppIdentity.name) 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
    private func windowTrackingItem(_ app: NSRunningApplication) -> AppItem? {
        if let regular = item(app) { return regular }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !app.isTerminated, app.activationPolicy == .accessory else { return nil }
        let registered = settings.profiles.flatMap(\.items).filter { $0.kind == .app }
        guard registered.contains(where: {
            ($0.bundleID != nil && $0.bundleID == app.bundleIdentifier)
                || app.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: $0.path).standardizedFileURL.path
        }) else { return nil }
        return AppItem(id: app.bundleIdentifier ?? app.bundleURL?.path ?? String(app.processIdentifier),
                       pid: app.processIdentifier, name: app.localizedName ?? "앱", url: app.bundleURL)
    }
    private func refreshWindows() {
        let all = NSWorkspace.shared.runningApplications.compactMap(windowTrackingItem)
        tracker.synchronize(apps: all, active: lastContext?.pid, trusted: trusted)
    }
    private func checkPermission(force: Bool = false) {
        let value = AXIsProcessTrusted()
        guard force || value != trusted else { return }
        let changed = value != trusted
        trusted = value
        menuUsage.refresh()
        if !value { windows = [] }
        hold.start()
        refreshWindows()
        if changed { refreshAppSettingsMenu() }
    }
    @objc func requestPermission() {
        hide()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    private func openAppManagementSettings() {
        pendingAction = nil
        hide()
        // Opens the page only. System authorization remains the user's choice.
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!)
    }
    @objc func openFromMenu() {
        show(held: false)
    }
    @objc private func reopenNotification(_ notification: Notification) {
        reopenExistingInterface(settings: notification.userInfo?["settings"] as? Bool == true, checkForUpdate: false)
    }
    private func reopenExistingInterface(settings: Bool = false, checkForUpdate: Bool = true) {
        // Finder/open may reuse this process even after the app at the same path
        // was rebuilt. Start a new instance so the normal handoff policy can run.
        if checkForUpdate {
            do {
                if try replacement.requestIfChanged(arguments: [settings ? "--settings" : "--show"], onFailure: { [weak self] in
                    self?.error("새 빌드를 열지 못했습니다. \($0)")
                }) { return }
            } catch {
                self.error("설치된 빌드를 확인하지 못했습니다. \(error.localizedDescription)")
                return
            }
        }
        // Reopening is also an explicit recovery opportunity after a temporary
        // menu/permission failure, even when the build has not changed.
        checkPermission(force: true)
        if settings { openSettings(); return }
        if let preferences, preferences.isVisible {
            NSApp.activate()
            preferences.makeKeyAndOrderFront(nil)
        } else { show(held: false) }
    }
    /// An overlay built ahead of time but not on screen yet.
    private struct PreparedOverlay {
        let panel: DeckPanel
        let content: OverlayContent
        let browser: FolderBrowser
        let hosting: NSView
        let screenFrame: CGRect
        let profileID: String
        let trusted: Bool
    }
    private var prepared: PreparedOverlay?

    /// Option went down: build the panel during the 0.25 s hold wait so the
    /// overlay only has to be ordered in when the wait ends. Nothing is shown,
    /// and shared presentation state is not touched until `show`.
    /// Keep this preload (R185/R191, user decision): data that changes during the
    /// hold is refreshed in `takePreparedOverlay`, not a reason to remove it.
    private func prepareOverlay() {
        guard panel?.isVisible != true, prepared == nil else { return }
        // No permission check here: a trust change restarts the hold monitor.
        // `show` checks it and rejects this overlay if trust changed meanwhile.
        updateApps()
        prepared = buildOverlay(restoring: nil, reportErrors: false)
    }
    private func discardPreparedOverlay() {
        prepared?.panel.contentView = nil
        prepared = nil
    }
    private func show(held: Bool, restoring previousLayout: PanelLayout? = nil) {
        guard panel?.isVisible != true else { return }
        optionReopen.cancel()
        checkPermission()
        updateApps()
        let ready = previousLayout == nil ? takePreparedOverlay() : nil
        discardPreparedOverlay()
        let overlay: PreparedOverlay
        if let ready { overlay = ready } else {
            guard let built = buildOverlay(restoring: previousLayout) else { return }
            overlay = built
        }
        present(overlay, held: held)
    }
    /// The prepared overlay if it still matches the cursor's screen, profile,
    /// permission and size; it is moved to the current cursor position.
    private func takePreparedOverlay() -> PreparedOverlay? {
        guard let ready = prepared, trusted == ready.trusted, settings.activeProfile.id == ready.profileID else { return nil }
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main,
              screen.visibleFrame == ready.screenFrame else { return nil }
        // Windows/app/menus may have changed during the hold. Update the prepared
        // content to the current data (as the pinned overlay's live refresh does)
        // instead of discarding the preload; only the size is recomputed.
        ready.content.refresh(context: lastContext, apps: apps, windows: windows, trusted: trusted,
                              commands: settings.commands, manualCount: settings.automatic ? nil : settings.manualCount,
                              menuHistory: settings.menuHistory, handoff: dockHandoff.current,
                              hasAppSettings: settings.showAppSettingsTile && appSettingsMenu.hasSettings(in: lastContext))
        let old = ready.content.snapshot.layout
        let moved = PanelLayout.calculate(visibleFrame: screen.visibleFrame, cursor: point, scale: PanelLayout.preferredScale)
            .fittingContent(registeredCount: settings.activeProfile.items.count, workRows: ready.content.snapshot.workRows())
        guard moved.compact == old.compact, moved.scale == old.scale else { return nil }
        if moved != old {
            ready.content.snapshot.layout = moved
            ready.panel.setFrame(moved.frame, display: false)
        }
        prepared = nil
        return ready
    }
    private func buildOverlay(restoring previousLayout: PanelLayout?, reportErrors: Bool = true) -> PreparedOverlay? {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main else { return nil }
        var layout: PanelLayout
        var layoutScreen = screen
        var restored = false
        if let previousLayout, let previousScreen = NSScreen.screens.first(where: { $0.visibleFrame.contains(previousLayout.frame) }) {
            layoutScreen = previousScreen
            restored = true
            layout = previousLayout.refittingContent(registeredCount: settings.activeProfile.items.count,
                                                       visibleFrame: previousScreen.visibleFrame)
        } else {
            layout = PanelLayout.calculate(visibleFrame: screen.visibleFrame, cursor: point, scale: PanelLayout.preferredScale)
                .fittingContent(registeredCount: settings.activeProfile.items.count)
        }
        guard layout.supported else {
            if reportErrors { error("작업 영역이 너무 작습니다. 화면 배율을 조절해 주세요. 최소 패널 크기는 512 × 420pt입니다.") }
            return nil
        }
        let menuNow = Date()
        let recent = OverlayContent.recentWindows(windows, context: lastContext, handoff: dockHandoff.current)
        let count = layout.windowLimit(manual: settings.automatic ? nil : settings.manualCount, actual: recent.count)
        var snapshot = OverlaySnapshot(context: lastContext,
                                       contextWindowTitle: windows.first { $0.pid == lastContext?.pid && !$0.isApplication }?.title,
                                       apps: Array(apps.prefix(3)),
                                       windows: Array(recent.prefix(count)), layout: layout, permission: trusted,
                                       pins: settings.pins, profileID: settings.activeProfile.id,
                                       profileName: settings.activeProfile.name, shortcuts: settings.numberShortcuts,
                                       commands: MenuCommand.ordered(settings.commands, appID: lastContext?.id ?? "", history: settings.menuHistory, at: menuNow),
                                       frequentMenuIDs: MenuCommand.frequentIDs(settings.commands, appID: lastContext?.id ?? "", history: settings.menuHistory, at: menuNow),
                                       hasAppSettings: settings.showAppSettingsTile && appSettingsMenu.hasSettings(in: lastContext))
        layout = restored
            ? layout.refittingContent(registeredCount: settings.activeProfile.items.count, visibleFrame: layoutScreen.visibleFrame,
                                      workRows: snapshot.workRows())
            : layout.fittingContent(registeredCount: settings.activeProfile.items.count, workRows: snapshot.workRows())
        snapshot.layout = layout
        snapshot.menuContextWindow = windows.first { $0.pid == lastContext?.pid && !$0.isApplication && $0.handoff == nil }
        let content = OverlayContent(snapshot)
        let folderBrowser = FolderBrowser()
        let view = DeckView(content: content, settings: settings, browser: folderBrowser, presentation: presentation, launches: launches,
                            selectApp: { [weak self] in self?.select(app: $0) },
                            selectPin: { [weak self] in self?.select(pin: $0) },
                            selectMenu: { [weak self] command, context, window in self?.select(menu: command, context: context, window: window) },
                            selectAppSettings: { [weak self] context, window in self?.selectAppSettings(context: context, window: window) },
                            changeProfile: { [weak self] id in self?.changeProfile(id) },
                            cycleProfile: { [weak self] step in self?.cycleProfile(step) },
                            selectWindow: { [weak self] in self?.select(window: $0) },
                            openURL: { [weak self] in self?.select(url: $0) },
                            openInFinder: { [weak self] in self?.selectFolderInFinder($0) },
                            openTrash: { [weak self] in self?.selectTrash() },
                            showSettings: { [weak self] destination in self?.showSettings(destination, context: content.snapshot.context) },
                            requestPermission: { [weak self] in self?.performImmediately { self?.requestPermission() } },
                            pinOverlay: { [weak self] in self?.pinOverlay() },
                            resizeForContent: { [weak self] count, rows in self?.resizeOverlay(registeredCount: count, workRows: rows) },
                            quitApplication: { [weak self] window in self?.requestQuit(windowless: window) },
                            dismiss: { [weak self] in
                                self?.pendingAction = nil
                                self?.hide()
                            })
        let hosting = NSHostingView(rootView: view)
        let surface = DeckSurfaceView(content: hosting, frame: CGRect(origin: .zero, size: layout.frame.size))
        let window = DeckPanel(contentRect: layout.frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        window.onClose = { [weak self] in
            self?.pendingAction = nil
            self?.hide()
        }
        window.onKeyEquivalent = { [weak self] in self?.hold.handleOverlayShortcut($0) ?? false }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isMovable = false
        window.contentView = surface
        window.setFrame(layout.frame, display: false)
        surface.layoutSubtreeIfNeeded()
        return PreparedOverlay(panel: window, content: content, browser: folderBrowser, hosting: hosting,
                               screenFrame: layoutScreen.visibleFrame, profileID: settings.activeProfile.id, trusted: trusted)
    }
    private func present(_ overlay: PreparedOverlay, held: Bool) {
        let window = overlay.panel
        visibleContent = overlay.content
        browser = overlay.browser
        presentation.reset()
        presentation.profile = settings.activeProfile
        profileScroll.reset()
        presentation.windowDesktops = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.desktop) })
        window.contentView?.layoutSubtreeIfNeeded()
        window.invalidateShadow()
        panel = window
        heldPresentation = held
        hold.isShowing = true
        // Both held and pinned overlays wait 0.4 s after each completed Dock
        // read. Slow reads cannot accumulate behind the click action.
        dockHandoff.startMonitoring()
        // Receive local shortcuts without activating the launcher or changing the
        // captured app context. Global monitors cannot consume another app's keys.
        window.makeKeyAndOrderFront(nil)
        if let index = CommandLine.arguments.firstIndex(of: "--render-check"),
           CommandLine.arguments.indices.contains(index + 1) {
            let path = CommandLine.arguments[index + 1]
            let hosting = overlay.hosting
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
    private func pinOverlay() {
        guard let panel, panel.isVisible else { return }
        pendingAction = nil
        presentation.selection = nil
        presentation.pin()
        // A held panel leaves the source app active. Pinning opts into normal
        // app keyboard ownership, including the macOS command/menu route.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        scheduleOverlayRefresh()
    }
    private func refreshAppSettingsMenu() {
        if settings.showAppSettingsTile { appSettingsMenu.refresh(app: lastContext) }
        else { appSettingsMenu.cancel() }
    }
    private func scheduleOverlayRefresh() {
        guard panel?.isVisible == true else { return }
        overlayRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshOverlayContent() }
        overlayRefresh = work
        // Coalesce activation + AX focus/title notifications without scanning menus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    private func refreshOverlayContent() {
        overlayRefresh = nil
        guard panel?.isVisible == true else { return }
        let mouseDown = NSEvent.pressedMouseButtons != 0
        guard OverlayRefreshPolicy.allows(hasSelection: presentation.selection != nil || presentation.execution != nil,
                                          hasPendingAction: pendingAction != nil, mouseDown: mouseDown) else {
            // Native window dragging may not deliver mouse-up. Retry only while
            // a known refresh is deferred by that gesture, never poll app contents.
            if mouseDown { scheduleOverlayRefresh() }
            return
        }
        visibleContent?.refresh(context: lastContext, apps: apps, windows: windows, trusted: trusted,
                                commands: settings.commands, manualCount: settings.automatic ? nil : settings.manualCount,
                                menuHistory: settings.menuHistory, handoff: dockHandoff.current,
                                hasAppSettings: settings.showAppSettingsTile && appSettingsMenu.hasSettings(in: lastContext))
        resizeOverlay(registeredCount: presentation.profile?.items.count ?? settings.activeProfile.items.count)
    }
    private func hide(reason: OverlayDismissal = .interruption, at time: TimeInterval = 0) {
        clearKeyboardFeedback()
        // A held overlay can be dragged now; reopen where it actually is.
        let shownLayout = visibleSnapshot.map { layout in
            PanelLayout(frame: panel?.frame ?? layout.layout.frame, compact: layout.layout.compact,
                        supported: layout.layout.supported, scale: layout.layout.scale)
        }
        optionReopen.record(shownLayout, at: time, reason: reason,
                            held: heldPresentation && panel?.isVisible == true,
                            actionPending: pendingAction != nil, preferences: settings.optionReopen)
        overlayRefresh?.cancel()
        overlayRefresh = nil
        dockHandoff.stopMonitoring()
        discardPreparedOverlay()
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        visibleContent = nil
        browser?.close()
        browser = nil
        hold.isShowing = false
        presentation.reset()
        profileScroll.reset()
    }
    private func performImmediately(retainingOverlay: Bool = false, _ action: () -> Void) {
        clearKeyboardFeedback()
        pendingAction = nil
        presentation.selection = nil
        if retainingOverlay {
            // Batch quit is an in-overlay action. Survive Option release and
            // app focus changes just like a user-pinned presentation.
            presentation.pin()
            if let panel, panel.isVisible {
                NSApp.activate()
                panel.makeKeyAndOrderFront(nil)
            }
        } else if !presentation.isPinned { hide() }
        action()
    }
    private func finishOptionSelection() {
        let action = pendingAction
        let target = presentation.selection
        let title = presentation.selectionTitle
        let pinned = presentation.isPinned
        pendingAction = nil
        presentation.selection = nil
        action?()
        if action != nil, pinned, presentation.isPinned, let target, let title {
            let id = presentation.showExecution(target: target, title: title)
            keyboardFeedbackCleanup?.cancel()
            let cleanup = DispatchWorkItem { [weak self] in
                self?.presentation.clearExecution(id: id)
                self?.keyboardFeedbackCleanup = nil
                self?.scheduleOverlayRefresh()
            }
            keyboardFeedbackCleanup = cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: cleanup)
        }
        scheduleOverlayRefresh()
    }
    private func clearKeyboardFeedback() {
        keyboardFeedbackCleanup?.cancel()
        keyboardFeedbackCleanup = nil
        presentation.clearExecution()
    }
    /// Isolated native verification: synthetic callbacks, no windows or app launch.
    func verifyClickExecutionForPreview() throws {
        hold.canTriggerHold = { false }
        hold.isShowing = true
        guard let option = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .option,
                                            timestamp: 1, windowNumber: 0, context: nil, characters: "",
                                            charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58) else {
            throw NSError(domain: "TileLauncher.Preview", code: 60)
        }
        _ = hold.handle(option, external: false)
        defer { hold.stop(); hold.onRelease = nil; pendingAction = nil; clearKeyboardFeedback(); presentation.reset() }
        for pinned in [false, true] {
            presentation.reset()
            if pinned { presentation.pin() }
            heldPresentation = true
            var clicks = 0, queued = 0
            pendingAction = { queued += 1 }
            presentation.selection = "pending-number"
            performImmediately { clicks += 1 }
            guard hold.optionDown, clicks == 1, queued == 0, pendingAction == nil,
                  presentation.selection == nil, presentation.isPinned == pinned else {
                throw NSError(domain: "TileLauncher.Preview", code: 61)
            }
            finishOptionSelection()
            guard clicks == 1, queued == 0 else { throw NSError(domain: "TileLauncher.Preview", code: 62) }
        }
        var numbers = 0
        presentation.pin()
        presentation.selection = "pin:preview"
        presentation.selectionTitle = "테스트 앱"
        pendingAction = { numbers += 1 }
        guard numbers == 0 else { throw NSError(domain: "TileLauncher.Preview", code: 63) }
        hold.onRelease = { [weak self] in self?.finishOptionSelection() }
        guard let release = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [],
                                             timestamp: 2, windowNumber: 0, context: nil, characters: "",
                                             charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58) else {
            throw NSError(domain: "TileLauncher.Preview", code: 63)
        }
        _ = hold.handle(release, external: false)
        _ = hold.handle(release, external: false)
        guard !hold.optionDown, numbers == 1, pendingAction == nil,
              presentation.execution?.target == "pin:preview", presentation.execution?.title == "테스트 앱",
              presentation.isPinned else {
            throw NSError(domain: "TileLauncher.Preview", code: 64)
        }
        for pinned in [false, true] {
            presentation.reset()
            if pinned { presentation.pin() }
            var quits = 0, queued = 0
            pendingAction = { queued += 1 }
            presentation.selection = "stale-number"
            let target = WindowItem(id: UUID(), pid: 123, appName: "Synthetic", appURL: nil, title: "Synthetic", minimized: false,
                                    isApplication: true)
            requestQuit(windowless: target, request: { _ in quits += 1; return nil })
            requestQuit(windowless: target, request: { _ in quits += 1; return nil })
            finishOptionSelection()
            guard quits == 2, queued == 0, pendingAction == nil, presentation.selection == nil,
                  presentation.isPinned, !presentation.dismisses(for: .release),
                  !presentation.dismisses(for: .outsideClick), presentation.dismisses(for: .escape) else {
                throw NSError(domain: "TileLauncher.Preview", code: 65)
            }
        }
        print("AppDelegate: immediate clicks/numbers preserved; batch quit pins the overlay, cancels queued actions and survives release/focus changes without terminating real apps.")
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
            let revision = profileChangeRevision
            refreshFocus { [weak self, weak originalPanel] in
                guard let self, let originalPanel, self.settings.followFocus,
                      self.profileChangeRevision == revision,
                      self.panel === originalPanel, originalPanel.isVisible else { return }
                self.redisplayProfile()
            }
        }
    }
    private func redisplayProfile() {
        displayProfile(settings.activeProfile)
    }
    private func displayProfile(_ profile: LauncherProfile) {
        guard panel?.isVisible == true else { return }
        pendingAction = nil
        presentation.selection = nil
        browser?.close()
        clearKeyboardFeedback()
        profileChangeRevision += 1
        presentation.profile = profile
        iconReadAhead?.prepareRegistered(profile.items)
        resizeOverlay(registeredCount: profile.items.count)
    }
    private func resizeOverlay(registeredCount: Int, workRows: CGFloat? = nil) {
        guard browser?.current == nil, let panel, panel.isVisible, let content = visibleContent,
              let screen = panel.screen ?? NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) }) else { return }
        let old = content.snapshot.layout
        let current = PanelLayout(frame: panel.frame, compact: old.compact, supported: old.supported, scale: old.scale)
        let fitted = current.refittingContent(registeredCount: registeredCount, visibleFrame: screen.visibleFrame,
                                             workRows: workRows ?? content.snapshot.workRows())
        guard fitted != old || fitted.frame != panel.frame else { return }
        content.snapshot.layout = fitted
        panel.setFrame(fitted.frame, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.invalidateShadow()
    }
    private func cycleProfile(_ step: Int) {
        guard let currentID = presentation.profile?.id ?? visibleSnapshot?.profileID,
              let next = ProfileNavigation.target(in: settings.profiles, currentID: currentID, step: step) else { return }
        // This is a presentation override, never a change to Focus or saved manual selection.
        displayProfile(next)
    }
    private func selectNumber(_ index: Int, command: Bool) {
        guard let snapshot = visibleSnapshot, browser?.current == nil else { NSSound.beep(); return }
        pendingAction = nil
        presentation.selection = nil
        if snapshot.shortcuts.targetsWindows(command: command) {
            guard snapshot.windows.indices.contains(index) else { NSSound.beep(); return }
            let window = snapshot.windows[index]
            if window.isApplication, let url = window.appURL, launches.isBlocked(url) { return }
            presentation.selection = "window:\(window.id)"
            presentation.selectionTitle = window.isApplication ? window.appName : "\(window.appName) — \(window.title)"
            pendingAction = { [weak self] in self?.select(window: window) }
        } else {
            let pins = presentation.profile?.items ?? snapshot.pins
            guard pins.indices.contains(index) else { NSSound.beep(); return }
            let pin = pins[index]
            if pin.kind == .app && launches.isBlocked(pin.url) { return }
            if pin.opensInOverlay {
                select(pin: pin)
                return
            }
            presentation.selection = "pin:\(pin.id)"
            presentation.selectionTitle = pin.name
            pendingAction = { [weak self] in self?.select(pin: pin) }
        }
    }
    private func select(pin: PinnedItem) {
        if pin.kind == .trash { selectTrash() }
        else if pin.kind == .app { launchApplication(at: pin.url, title: pin.name) }
        else if pin.opensInOverlay {
            pendingAction = nil
            presentation.selection = nil
            browser?.open(pin)
        }
        else { selectFolderInFinder(pin.url) }
    }
    private func select(menu: MenuCommand, context: AppItem?, window: WindowItem?) {
        guard let context, context.id == menu.appID else { return }
        performMenu(in: context, window: window) { [weak self] in
            self?.menuUsage.suppressLauncherAction(menu)
            self?.menuCatalog.execute(menu, in: context, shortcut: { [weak self] in
                self?.settings.updateShortcut($0, for: menu.id)
            }) { [weak self] message in
                if let message { self?.error(message) } else {
                    self?.settings.recordUse(menu.id)
                    self?.scheduleOverlayRefresh()
                }
            }
        }
    }
    private func selectAppSettings(context: AppItem?, window: WindowItem?) {
        guard settings.showAppSettingsTile, let context else { return }
        performMenu(in: context, window: window) { [weak self] in
            self?.appSettingsMenu.execute(in: context, prepare: { [weak self] command, press in
                self?.menuUsage.suppressLauncherAction(command, completion: press)
            }) { [weak self] message in
                if let message { self?.error(message) }
            }
        }
    }
    private func performMenu(in context: AppItem, window: WindowItem?, run: @escaping () -> Void) {
        performImmediately { [weak self] in
            guard let self else { return }
            guard let running = NSRunningApplication(processIdentifier: context.pid), !running.isTerminated else {
                self.error("메뉴를 사용할 앱이 종료되었습니다.")
                return
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
        if let url = app.url, launches.isBlocked(url) { return }
        performImmediately { [weak self] in
            guard let running = NSRunningApplication(processIdentifier: app.pid) else {
                self?.error("앱이 종료되었습니다.")
                return
            }
            NSApp.yieldActivation(to: running)
            if !running.activate(options: []) { self?.error("앱을 활성화하지 못했습니다.") }
        }
    }
    private func select(window: WindowItem) {
        if let handoff = window.handoff {
            performImmediately { [weak self] in
                self?.dockHandoff.press(handoff) { message in if let message { self?.error(message) } }
            }
            return
        }
        if window.isApplication, let url = window.appURL, launches.isBlocked(url) { return }
        performImmediately { [weak self] in
            self?.tracker.focus(id: window.id) { message in
                if let message { self?.error(message) }
            }
        }
    }
    private func requestQuit(windowless window: WindowItem,
                             request: (NSRunningApplication?) -> String? = ApplicationTermination.request) {
        guard window.isApplication else { return }
        performImmediately(retainingOverlay: true) { [weak self] in
            if let message = request(window.runningApplication) { self?.error(message) }
            self?.scheduleOverlayRefresh()
        }
    }
    private func select(url: URL) {
        if url.pathExtension.lowercased() == "app" {
            launchApplication(at: url)
            return
        }
        performImmediately { [weak self] in
            if !NSWorkspace.shared.open(url) { self?.error("항목을 열지 못했습니다. 이동되었거나 삭제되었는지 확인해 주세요.") }
        }
    }
    private func launchApplication(at url: URL, title: String? = nil) {
        guard !launches.isBlocked(url) else { return }
        performImmediately { [weak self] in
            self?.launches.launch(at: url, title: title ?? url.deletingPathExtension().lastPathComponent) { [weak self] message in
                self?.error(message)
            }
        }
    }
    @objc func openSettings() {
        showSettings(.general, context: lastContext)
    }
    private func showSettings(_ destination: SettingsDestination, context: AppItem?) {
        pendingAction = nil
        hide()
        settingsNavigation.open(destination, app: context)
        if let preferences {
            preferencesEditor?.activate()
            if !preferences.isVisible {
                sizeSettingsWindow(preferences)
                preferences.center()
            }
            NSApp.activate()
            preferences.makeKeyAndOrderFront(nil)
            return
        }
        let editor = SettingsEditingSession(source: settings)
        preferencesEditor = editor
        let view = SettingsView(settings: settings, loginItem: loginItem, navigation: settingsNavigation,
                                requestPermission: requestPermission, openAppManagementSettings: openAppManagementSettings,
                                editor: editor)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsWindowLayout.defaultWidth, height: 660),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "\(AppIdentity.name) 설정"
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: view)
        sizeSettingsWindow(window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        preferences = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === preferences else { return }
        preferencesEditor?.registered.cancelDockImport()
        preferencesEditor?.pause()
    }
    private func sizeSettingsWindow(_ window: NSWindow) {
        MainActor.assumeIsolated {
            loginItem.refresh()
            let size = SettingsWindowLayout.fittedContentSize(settings: settings, loginItem: loginItem)
            SettingsWindowLayout.apply(to: window, contentSize: size,
                                       visibleFrame: window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
        }
    }
    private func error(_ message: String) {
        let alert = NSAlert()
        alert.messageText = AppIdentity.name
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        NSApp.activate()
        alert.runModal()
    }
    private func selectFolderInFinder(_ url: URL) {
        performImmediately { [weak self] in
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
        performImmediately { [weak self] in
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
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        dockHandoff.stopMonitoring()
        appSettingsMenu.cancel()
        iconReadAhead?.stop()
        hold.stop()
        menuUsage.stop()
        permissionTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }
}

// Register with AppKit, then acquire before constructing monitors or the status item.
let application = NSApplication.shared
if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
    // Xcode's canvas owns its preview hosts. Never install global monitors,
    // acquire the user's app instance lock or create a status item here.
    application.setActivationPolicy(.prohibited)
    application.run()
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
   CommandLine.arguments.indices.contains(index + 1) {
    application.setActivationPolicy(.prohibited)
    do {
        try MainActor.assumeIsolated {
            try PreviewExport.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
        }
        exit(0)
    } catch {
        fputs("Preview export failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}
// R183 glass comparison: synthetic panels only, bypasses the production instance.
if let index = CommandLine.arguments.firstIndex(of: "--check-menu-icons"), CommandLine.arguments.indices.contains(index + 1) {
    application.setActivationPolicy(.prohibited)
    do {
        try MainActor.assumeIsolated {
            try MenuIconValidation.verify(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
        }
        exit(0)
    } catch { fputs("Menu icon check failed: \(error.localizedDescription)\n", stderr); exit(1) }
}
if let index = CommandLine.arguments.firstIndex(of: "--glass-compare") {
    application.setActivationPolicy(.accessory)
    let seconds = CommandLine.arguments.indices.contains(index + 1)
        ? TimeInterval(CommandLine.arguments[index + 1]) ?? 120 : 120
    MainActor.assumeIsolated { GlassComparison.show(seconds: seconds) }
    application.run()
    exit(0)
}
// R192 uncommitted press test: `--press-handoff <output.json> [seconds]`.
if let index = CommandLine.arguments.firstIndex(of: "--press-handoff"), CommandLine.arguments.indices.contains(index + 1) {
    application.setActivationPolicy(.prohibited)
    let seconds = CommandLine.arguments.indices.contains(index + 2) ? TimeInterval(CommandLine.arguments[index + 2]) ?? 600 : 600
    DockDiagnostics.press(output: URL(fileURLWithPath: CommandLine.arguments[index + 1]), seconds: seconds)
    application.run()
    exit(0)
}
// R192 read-only Dock probe: `--diagnose-dock <output.jsonl> [seconds]`. Bypasses the
// production instance; never presses Dock items.
if let index = CommandLine.arguments.firstIndex(of: "--diagnose-dock"), CommandLine.arguments.indices.contains(index + 1) {
    application.setActivationPolicy(.prohibited)
    let seconds = CommandLine.arguments.indices.contains(index + 2) ? TimeInterval(CommandLine.arguments[index + 2]) ?? 120 : 120
    DockDiagnostics.run(output: URL(fileURLWithPath: CommandLine.arguments[index + 1]), seconds: seconds)
    application.run()
    exit(0)
}
// Targeted read-only inventory diagnostics bypass the production instance and all UI.
if let index = CommandLine.arguments.firstIndex(of: "--diagnose-window-inventory") {
    application.setActivationPolicy(.prohibited)
    let ids = Set(CommandLine.arguments.dropFirst(index + 1))
    guard !ids.isEmpty, AXIsProcessTrusted() else {
        fputs("Inventory diagnostics need bundle IDs and existing AX trust; no prompt is shown.\n", stderr)
        exit(2)
    }
    let targets = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier.map(ids.contains) == true }
    let probe = WindowTracker()
    probe.onChange = { items in
        let rows: [[String: Any]] = items.map {
            ["app": $0.appName, "pid": $0.pid, "applicationOnly": $0.isApplication,
             "windowID": $0.windowID.map { NSNumber(value: $0) } ?? NSNull(), "desktop": $0.desktop.rawValue]
        }
        let data = try! JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        exit(0)
    }
    probe.synchronize(apps: targets.map { AppItem(id: $0.bundleIdentifier!, pid: $0.processIdentifier,
                                                 name: $0.localizedName ?? "", url: $0.bundleURL) },
                      active: nil, trusted: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { fputs("Inventory diagnostic timeout.\n", stderr); exit(3) }
    withExtendedLifetime(probe) { application.run() }
    exit(0)
}
let instanceLock: InstanceLock
let runningBuild: AppBuild
do {
    runningBuild = try InstanceCoordinator.build(at: Bundle.main.bundleURL)
    guard let lock = try InstanceCoordinator.acquire(build: runningBuild) else { exit(0) }
    instanceLock = lock
} catch {
    let alert = NSAlert()
    alert.messageText = "\(AppIdentity.name)를 시작하지 못했습니다."
    alert.informativeText = "중복 실행 확인에 실패했습니다. \(error.localizedDescription)"
    alert.runModal()
    exit(1)
}
let delegate = AppDelegate(build: runningBuild)
application.delegate = delegate
withExtendedLifetime(instanceLock) { application.run() }
