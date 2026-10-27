import AppKit
import Combine
import DeckCore
import SwiftUI

struct ApplicationLaunchBusy: View {
    var compact = false
    @Environment(\.deckScale) private var scale
    @Environment(\.deckTheme) private var theme
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.isClassic ? 0 : (compact ? 8 : 12) * scale)
                .fill(Color.primary.opacity(0.14))
            ProgressView().controlSize(.small).padding(compact ? 4 : 7)
                .background(.regularMaterial, in: Circle())
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Tracks only launches requested here. Closing/reopening an overlay does not
/// discard the in-flight app, and an old callback cannot unlock a newer request.
final class ApplicationLaunchMonitor: ObservableObject {
    private final class Request {
        let id = UUID()
        let key: String
        let title: String
        let identity: ApplicationLaunchIdentity
        let previousPIDs: Set<pid_t>
        var gate: ApplicationLaunchGate
        var app: NSRunningApplication?
        var observations: [NSKeyValueObservation] = []
        init(url: URL, title: String, now: TimeInterval, running: [NSRunningApplication]) {
            key = ApplicationLaunchMonitor.key(url)
            self.title = title
            let bundle = Bundle(url: url)
            identity = ApplicationLaunchIdentity(bundlePath: key, bundleID: bundle?.bundleIdentifier,
                executablePath: bundle?.executableURL.map(ApplicationLaunchMonitor.key))
            previousPIDs = Set(running.map(\.processIdentifier))
            gate = ApplicationLaunchGate(now: now)
        }
    }
    @Published private(set) var states: [String: ApplicationLaunchStatus] = [:]
    @Published private(set) var statusText: String?
    private var requests: [String: Request] = [:]
    private var generations: [String: UUID] = [:]
    private var workspaceObservation: NSKeyValueObservation?
    private var timer: Timer?
    private var noticeRevision = UUID()
    private var latestKey: String?

    typealias OpenApplication = (URL, @escaping (NSRunningApplication?, Error?) -> Void) -> Void
    private let now: () -> TimeInterval
    private let running: () -> [NSRunningApplication]
    private let open: OpenApplication
    private let observesSystem: Bool

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         running: @escaping () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications },
         observesSystem: Bool = true, open: @escaping OpenApplication = { url, completion in
             let configuration = NSWorkspace.OpenConfiguration()
             configuration.activates = true
             configuration.addsToRecentItems = false
             NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: completion)
         }) {
        self.now = now; self.running = running; self.observesSystem = observesSystem; self.open = open
    }

    static func key(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
    func isBlocked(_ url: URL) -> Bool { states[Self.key(url)]?.blocksLaunch == true }

    /// Stronger evidence than an elapsed timer or menu-bar activation: the tracker
    /// confirmed a specific focused window on the current desktop. Only release
    /// an in-flight request bound to this exact living process.
    func confirmWindowReady(pid: pid_t) {
        precondition(Thread.isMainThread)
        guard !requests.isEmpty,
              let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated else { return }
        for request in Array(requests.values) {
            guard let bound = request.app, !bound.isTerminated, bound.isEqual(running) else { continue }
            let status = request.gate.update(processFound: true, finished: running.isFinishedLaunching,
                                             windowReady: true, now: now())
            finish(request, status: status)
        }
    }

    @discardableResult func launch(at url: URL, title: String, failure: @escaping (String) -> Void) -> Bool {
        precondition(Thread.isMainThread)
        let key = Self.key(url)
        guard requests[key] == nil else { return false }
        let request = Request(url: url, title: title, now: now(), running: running())
        requests[key] = request
        generations[key] = request.id
        latestKey = key
        noticeRevision = UUID()
        states[key] = .waiting
        statusText = "\(title) · 실행 준비 중…"
        if observesSystem && workspaceObservation == nil {
            // Unlike will/didLaunch notifications this also covers LSUIElement apps.
            workspaceObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        }
        if observesSystem && timer == nil {
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        open(url) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.generations[key] == request.id else { return }
                if let error {
                    if self.requests[key]?.id == request.id { self.finish(request, status: .failed) }
                    failure("앱을 열지 못했습니다. \(error.localizedDescription)")
                } else if let app, self.requests[key]?.id == request.id {
                    self.attach(app, to: request, authoritative: true)
                    self.refresh()
                }
            }
        }
        refresh()
        return true
    }

    private func attach(_ app: NSRunningApplication, to request: Request, authoritative: Bool = false) {
        // The open completion identifies the process actually opened by AppKit.
        // Inventory guesses must never prevent that authoritative correction.
        guard request.app == nil || (authoritative && request.app?.isEqual(app) != true) else { return }
        request.observations.removeAll()
        request.app = app
        let changed: () -> Void = { [weak self, weak request] in
            DispatchQueue.main.async {
                guard let self, let request, self.requests[request.key]?.id == request.id else { return }
                self.refresh()
            }
        }
        guard observesSystem else { return }
        request.observations = [app.observe(\.isFinishedLaunching, options: [.new]) { _, _ in changed() },
                                app.observe(\.isTerminated, options: [.new]) { _, _ in changed() }]
    }

    private func refresh() {
        guard !requests.isEmpty else { return }
        let running = running()
        for request in Array(requests.values) {
            if request.app == nil {
                // Canonicalize paths only for processes with the expected identifier.
                let exact = running.first { app in
                    !app.isTerminated && request.identity.matches(bundleID: app.bundleIdentifier,
                        bundlePath: { app.bundleURL.map(Self.key) }, executablePath: { app.executableURL.map(Self.key) })
                }
                let found = exact ?? running.first { app in
                    !app.isTerminated && !request.previousPIDs.contains(app.processIdentifier)
                        && request.identity.admitsNewProcess(bundleID: app.bundleIdentifier,
                                                             executableName: { app.executableURL?.lastPathComponent })
                }
                if let found { attach(found, to: request) }
            }
            let status = request.gate.update(processFound: request.app != nil,
                finished: request.app?.isFinishedLaunching == true, terminated: request.app?.isTerminated == true,
                now: now())
            if status.blocksLaunch {
                if states[request.key] != status { states[request.key] = status }
                if latestKey == request.key {
                    let text = "\(request.title) · \(status == .waiting ? "실행 준비 중…" : "실행 중…")"
                    if statusText != text { statusText = text }
                }
            } else { finish(request, status: status) }
        }
    }

    private func finish(_ request: Request, status: ApplicationLaunchStatus) {
        guard requests[request.key]?.id == request.id else { return }
        requests[request.key] = nil
        states[request.key] = nil
        request.observations.removeAll()
        if status == .finished || status == .windowReady {
            // A late launch callback cannot undo an already verified success.
            generations[request.key] = nil
        }
        if latestKey == request.key {
            let suffix: String
            switch status {
            case .finished: suffix = "실행 완료"
            case .windowReady: suffix = "창 준비 완료"
            case .notStarted: suffix = "시작을 확인하지 못해 대기를 해제했어요"
            case .stopped: suffix = "앱이 종료되어 대기를 해제했어요"
            case .timedOut: suffix = "완료 신호가 없어 대기를 해제했어요"
            default: suffix = "실행 요청을 마쳤어요"
            }
            statusText = "\(request.title) · \(suffix)"
            let revision = UUID()
            noticeRevision = revision
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.noticeRevision == revision else { return }
                self.statusText = nil
            }
        }
        if requests.isEmpty {
            timer?.invalidate(); timer = nil
            workspaceObservation = nil
        }
    }
    #if TILE_LAUNCHER_DIAGNOSTICS
    /// Exercises real monitor coordination with synthetic requests; never opens an app.
    @MainActor static func verifyForPreview() throws {
        var clock: TimeInterval = 0
        var completions: [(NSRunningApplication?, Error?) -> Void] = []
        var errors = 0
        let monitor = ApplicationLaunchMonitor(now: { clock }, running: { [] }, observesSystem: false) {
            _, completion in completions.append(completion)
        }
        let url = URL(fileURLWithPath: "/tmp/TileLaunchPreview.app")
        let other = URL(fileURLWithPath: "/tmp/AnotherLaunchPreview.app")
        func launch() -> Bool { monitor.launch(at: url, title: "테스트", failure: { _ in errors += 1 }) }
        func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        guard launch(), monitor.isBlocked(url), !monitor.isBlocked(other), !launch(), completions.count == 1 else {
            throw NSError(domain: "TileLauncher.Preview", code: 90)
        }
        clock = 3; monitor.refresh()
        guard !monitor.isBlocked(url), launch(), completions.count == 2 else {
            throw NSError(domain: "TileLauncher.Preview", code: 91)
        }
        completions[0](nil, NSError(domain: "stale", code: 1)); drain()
        guard monitor.isBlocked(url), errors == 0 else { throw NSError(domain: "TileLauncher.Preview", code: 92) }
        completions[1](nil, NSError(domain: "current", code: 1)); drain()
        guard !monitor.isBlocked(url), errors == 1, launch() else { throw NSError(domain: "TileLauncher.Preview", code: 93) }
        // This headless preview may never call NSApp.run / finishLaunching.
        // Verify that the monitor respects its real state, not callback success alone.
        completions[2](NSRunningApplication.current, nil); drain()
        // System observation is intentionally disabled in this fixture. The
        // headless process may finish launching during drain(), so sample its
        // latest state explicitly before comparing it with the monitor.
        monitor.refresh()
        let blocked = monitor.isBlocked(url), finished = NSRunningApplication.current.isFinishedLaunching
        // A native terminated state also releases the gate; callback success
        // alone never proves that a headless process finished launching.
        let terminated = NSRunningApplication.current.isTerminated
        guard blocked == (!finished && !terminated), errors == 1 else {
            let attached = monitor.requests[Self.key(url)]?.app != nil
            throw NSError(domain: "TileLauncher.Preview", code: 94, userInfo: [NSLocalizedDescriptionKey:
                "Native launch fixture: blocked=\(blocked), finished=\(finished), terminated=\(terminated), attached=\(attached), errors=\(errors), completions=\(completions.count)"])
        }
        // Exercise the actual replacement and observation wiring, using two
        // existing processes without activating or launching either one.
        if let prior = NSWorkspace.shared.runningApplications.first(where: {
            !$0.isTerminated && $0.processIdentifier != getpid()
        }) {
            let corrected = ApplicationLaunchMonitor(now: { 0 }, running: { [] }, observesSystem: false,
                                                      open: { _, _ in })
            corrected.launch(at: url, title: "테스트", failure: { _ in })
            let correction = corrected.requests[Self.key(url)]!
            corrected.attach(prior, to: correction)
            corrected.attach(NSRunningApplication.current, to: correction)
            guard correction.app?.isEqual(prior) == true else {
                throw NSError(domain: "TileLauncher.Preview", code: 97)
            }
            corrected.attach(NSRunningApplication.current, to: correction, authoritative: true)
            guard correction.app?.isEqual(NSRunningApplication.current) == true else {
                throw NSError(domain: "TileLauncher.Preview", code: 98)
            }
        }
        var verifiedCompletion: ((NSRunningApplication?, Error?) -> Void)?
        var verifiedErrors = 0
        let verified = ApplicationLaunchMonitor(now: { 0 }, running: { [] }, observesSystem: false,
                                                open: { _, done in verifiedCompletion = done })
        verified.launch(at: url, title: "테스트", failure: { _ in verifiedErrors += 1 })
        let pending = verified.requests[Self.key(url)]!
        pending.app = NSRunningApplication.current
        verified.confirmWindowReady(pid: -1)
        guard verified.isBlocked(url) else { throw NSError(domain: "TileLauncher.Preview", code: 95) }
        // A focused window of another living process is read only, never
        // activated, and cannot release a request bound to this process.
        if let other = NSWorkspace.shared.runningApplications.first(where: {
            !$0.isTerminated && $0.processIdentifier != getpid()
        }) {
            verified.confirmWindowReady(pid: other.processIdentifier)
            guard verified.isBlocked(url) else { throw NSError(domain: "TileLauncher.Preview", code: 99) }
        }
        // The native completion signal keeps its own meaning; window evidence
        // only releases a process that has not reported finished launching.
        let finishedBeforeWindow = NSRunningApplication.current.isFinishedLaunching
        verified.confirmWindowReady(pid: NSRunningApplication.current.processIdentifier)
        guard verified.statusText == "테스트 · \(finishedBeforeWindow ? "실행 완료" : "창 준비 완료")" else {
            throw NSError(domain: "TileLauncher.Preview", code: 100, userInfo: [NSLocalizedDescriptionKey:
                "Window readiness status: finished=\(finishedBeforeWindow), text=\(verified.statusText ?? "nil")"])
        }
        verifiedCompletion?(nil, NSError(domain: "LateAfterVerifiedWindow", code: 1)); drain()
        guard !verified.isBlocked(url), verified.requests.isEmpty, verifiedErrors == 0 else {
            throw NSError(domain: "TileLauncher.Preview", code: 96)
        }
        // Requests are keyed by the resolved bundle: a symlink shares the real
        // app's gate, while a separate copy keeps its own.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TileLaunchKey-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("Real.app", isDirectory: true)
        let copy = root.appendingPathComponent("Copy.app", isDirectory: true)
        let link = root.appendingPathComponent("Link.app")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let aliases = ApplicationLaunchMonitor(now: { 0 }, running: { [] }, observesSystem: false, open: { _, _ in })
        guard aliases.launch(at: link, title: "테스트", failure: { _ in }), aliases.isBlocked(real),
              !aliases.isBlocked(copy), !aliases.launch(at: real, title: "테스트", failure: { _ in }) else {
            throw NSError(domain: "TileLauncher.Preview", code: 101)
        }
        print("Launch monitor: duplicate suppression, unrelated process rejection, other live PID rejection, verified window readiness vs native completion, symlink/copy keys, start timeout, stale callback, error retry and native launch state passed without launching apps.")
    }
    #endif
    deinit { timer?.invalidate() }
}
