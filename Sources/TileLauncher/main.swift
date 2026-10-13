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

final class AppDelegate: NSObject, NSApplicationDelegate {
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
    let menuCatalog = MenuCatalog()
    private lazy var menuUsage = MenuUsageMonitor(settings: settings)
    private var visibleContent: OverlayContent?
    private var visibleSnapshot: OverlaySnapshot? { visibleContent?.snapshot }
    private var pinnedRefresh: DispatchWorkItem?
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
    private var optionReopen = OptionReopenMemory<PanelLayout>()
    private var browser: FolderBrowser?
    private var scrollMonitor: Any?
    private var profileScroll = ProfileScrollGesture()
    private var profileChangeRevision = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            self.schedulePinnedRefresh()
        }
        hold.onShow = { [weak self] in self?.show(held: true) }
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
        hold.onCancel = { [weak self] in self?.pendingAction = nil; self?.presentation.selection = nil }
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
        menuUsage.onCapture = { [weak self] in self?.schedulePinnedRefresh() }
        menuUsage.start()
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
            self.schedulePinnedRefresh()
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
    private func refreshWindows() {
        let all = NSWorkspace.shared.runningApplications.compactMap(item)
        tracker.synchronize(apps: all, active: lastContext?.pid, trusted: trusted)
    }
    private func checkPermission(force: Bool = false) {
        let value = AXIsProcessTrusted()
        guard force || value != trusted else { return }
        trusted = value
        menuUsage.refresh()
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
    private func openAppManagementSettings() {
        pendingAction = nil
        hide()
        // Opens the page only. System authorization remains the user's choice.
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!)
    }
    @objc func openFromMenu() { show(held: false) }
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
    private func show(held: Bool, restoring previousLayout: PanelLayout? = nil) {
        guard panel?.isVisible != true else { return }
        optionReopen.cancel()
        checkPermission()
        updateApps()
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main else { return }
        let layout: PanelLayout
        if let previousLayout, NSScreen.screens.contains(where: { $0.visibleFrame.contains(previousLayout.frame) }) {
            layout = previousLayout
        } else {
            layout = PanelLayout.calculate(visibleFrame: screen.visibleFrame, cursor: point)
                .fittingContent(registeredCount: settings.profiles.map { $0.items.count }.max() ?? 0)
        }
        guard layout.supported else {
            error("작업 영역이 너무 작습니다. 화면 배율을 조절해 주세요. 최소 패널 크기는 512 × 420pt입니다.")
            return
        }
        let count = layout.windowLimit(manual: settings.automatic ? nil : settings.manualCount, actual: windows.count)
        let menuNow = Date()
        let snapshot = OverlaySnapshot(context: lastContext,
                                       contextWindowTitle: windows.first { $0.pid == lastContext?.pid }?.title,
                                       apps: Array(apps.prefix(3)),
                                       windows: Array(windows.prefix(count)), layout: layout, permission: trusted,
                                       pins: settings.pins, profileID: settings.activeProfile.id,
                                       profileName: settings.activeProfile.name, shortcuts: settings.numberShortcuts,
                                       commands: MenuCommand.ordered(settings.commands, appID: lastContext?.id ?? "", history: settings.menuHistory, at: menuNow),
                                       frequentMenuIDs: MenuCommand.frequentIDs(settings.commands, appID: lastContext?.id ?? "", history: settings.menuHistory, at: menuNow))
        let content = OverlayContent(snapshot)
        visibleContent = content
        let folderBrowser = FolderBrowser()
        browser = folderBrowser
        presentation.reset()
        presentation.profile = settings.activeProfile
        profileScroll.reset()
        presentation.windowDesktops = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.desktop) })
        let view = DeckView(content: content, settings: settings, browser: folderBrowser, presentation: presentation,
                            selectApp: { [weak self] in self?.select(app: $0) },
                            selectPin: { [weak self] in self?.select(pin: $0) },
                            selectMenu: { [weak self] command, context, window in self?.select(menu: command, context: context, window: window) },
                            changeProfile: { [weak self] id in self?.changeProfile(id) },
                            cycleProfile: { [weak self] step in self?.cycleProfile(step) },
                            selectWindow: { [weak self] in self?.select(window: $0) },
                            openURL: { [weak self] in self?.select(url: $0) },
                            openInFinder: { [weak self] in self?.selectFolderInFinder($0) },
                            openTrash: { [weak self] in self?.selectTrash() },
                            showSettings: { [weak self] destination in self?.showSettings(destination, context: content.snapshot.context) },
                            requestPermission: { [weak self] in self?.performImmediately { self?.requestPermission() } },
                            pinOverlay: { [weak self] in self?.pinOverlay() },
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
        window.invalidateShadow()
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
    private func pinOverlay() {
        guard let panel, panel.isVisible else { return }
        pendingAction = nil
        presentation.selection = nil
        presentation.pin()
        // A held panel leaves the source app active. Pinning opts into normal
        // app keyboard ownership, including the macOS command/menu route.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        schedulePinnedRefresh()
    }
    private func schedulePinnedRefresh() {
        guard panel?.isVisible == true, presentation.isPinned else { return }
        pinnedRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshPinnedContent() }
        pinnedRefresh = work
        // Coalesce activation + AX focus/title notifications without scanning menus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    private func refreshPinnedContent() {
        pinnedRefresh = nil
        guard panel?.isVisible == true else { return }
        let mouseDown = NSEvent.pressedMouseButtons != 0
        guard PinnedRefreshPolicy.allows(isPinned: presentation.isPinned, optionDown: hold.optionDown,
                                        hasSelection: presentation.selection != nil,
                                        hasPendingAction: pendingAction != nil, mouseDown: mouseDown) else {
            // Native window dragging may not deliver mouse-up. Retry only while
            // a known refresh is deferred by that gesture, never poll app contents.
            if mouseDown && presentation.isPinned && !hold.optionDown { schedulePinnedRefresh() }
            return
        }
        visibleContent?.refresh(context: lastContext, apps: apps, windows: windows, trusted: trusted,
                                commands: settings.commands, manualCount: settings.automatic ? nil : settings.manualCount,
                                menuHistory: settings.menuHistory)
    }
    private func hide(reason: OverlayDismissal = .interruption, at time: TimeInterval = 0) {
        optionReopen.record(visibleSnapshot?.layout, at: time, reason: reason,
                            held: heldPresentation && panel?.isVisible == true,
                            actionPending: pendingAction != nil, preferences: settings.optionReopen)
        pinnedRefresh?.cancel()
        pinnedRefresh = nil
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
    private func performImmediately(_ action: () -> Void) {
        pendingAction = nil
        presentation.selection = nil
        if !presentation.isPinned { hide() }
        action()
    }
    private func finishOptionSelection() {
        let action = pendingAction
        pendingAction = nil
        presentation.selection = nil
        action?()
        schedulePinnedRefresh()
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
        defer { hold.stop(); hold.onRelease = nil; pendingAction = nil; presentation.reset() }
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
        guard !hold.optionDown, numbers == 1, pendingAction == nil else {
            throw NSError(domain: "TileLauncher.Preview", code: 64)
        }
        print("AppDelegate: immediate click while Option held, pinned retention, queued-number cancellation and exactly-once deferred number execution passed.")
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
        profileChangeRevision += 1
        presentation.profile = profile
    }
    private func cycleProfile(_ step: Int) {
        guard let currentID = presentation.profile?.id ?? visibleSnapshot?.profileID,
              let next = ProfileNavigation.target(in: settings.profiles, currentID: currentID, step: step) else { return }
        // This is a presentation override, never a change to Focus or saved manual selection.
        displayProfile(next)
    }
    private func selectNumber(_ index: Int, command: Bool) {
        guard let snapshot = visibleSnapshot, browser?.current == nil else { NSSound.beep(); return }
        if snapshot.shortcuts.targetsWindows(command: command) {
            guard snapshot.windows.indices.contains(index) else { NSSound.beep(); return }
            let window = snapshot.windows[index]
            presentation.selection = "window:\(window.id)"
            pendingAction = { [weak self] in self?.select(window: window) }
        } else {
            let pins = presentation.profile?.items ?? snapshot.pins
            guard pins.indices.contains(index) else { NSSound.beep(); return }
            let pin = pins[index]
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
        else if pin.kind == .app { launchApplication(at: pin.url) }
        else if pin.opensInOverlay {
            pendingAction = nil
            presentation.selection = nil
            browser?.open(pin)
        }
        else { selectFolderInFinder(pin.url) }
    }
    private func select(menu: MenuCommand, context: AppItem?, window: WindowItem?) {
        guard let context, context.id == menu.appID else { return }
        performImmediately { [weak self] in
            guard let self else { return }
            guard let running = NSRunningApplication(processIdentifier: context.pid), !running.isTerminated else {
                self.error("메뉴를 사용할 앱이 종료되었습니다.")
                return
            }
            let run = { [weak self] in
                self?.menuUsage.suppressLauncherAction(menu)
                self?.menuCatalog.execute(menu, in: context) { [weak self] message in
                    if let message { self?.error(message) } else {
                        self?.settings.recordUse(menu.id)
                        self?.schedulePinnedRefresh()
                    }
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
        performImmediately { [weak self] in
            self?.tracker.focus(id: window.id) { message in
                if let message { self?.error(message) }
            }
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
    private func launchApplication(at url: URL) {
        performImmediately { [weak self] in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, failure in
                if let failure {
                    DispatchQueue.main.async { self?.error("앱을 열지 못했습니다. \(failure.localizedDescription)") }
                }
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
            NSApp.activate()
            preferences.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(settings: settings, loginItem: loginItem, navigation: settingsNavigation,
                                requestPermission: requestPermission, openAppManagementSettings: openAppManagementSettings)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "\(AppIdentity.name) 설정"
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
