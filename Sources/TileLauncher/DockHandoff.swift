import AppKit
import ApplicationServices
import DeckCore

/// A Handoff (Continuity) activity offered by another device, as the Dock shows it.
struct HandoffItem: Equatable {
    /// The Mac app that will continue the activity (the Dock item's title).
    let appName: String
    let appURL: URL?
    /// The sending device's model identifier, e.g. `com.apple.iphone-15-pro-1`.
    let device: String
    /// SF Symbol for the sending device.
    var deviceSymbol: String {
        let model = device.lowercased()
        if model.contains("ipad") { return "ipad" }
        if model.contains("watch") { return "applewatch" }
        if model.contains("vision") { return "visionpro" }
        if model.contains("mac") { return "laptopcomputer" }
        return "iphone"
    }
    var deviceName: String {
        switch deviceSymbol {
        case "ipad": "iPad"
        case "applewatch": "Apple Watch"
        case "visionpro": "Apple Vision Pro"
        case "laptopcomputer": "Mac"
        default: "iPhone"
        }
    }
}

/// R192: reads and presses the Dock's Handoff item through Accessibility.
/// There is no public API for other devices' activities; the Dock exposes the
/// item as AXDockItem / AXHandoffDockItem (verified on macOS 27.2 by a read-only
/// probe and a single press test). Reads run off the main thread.
final class DockHandoff {
    static let subrole = "AXHandoffDockItem"
    private let queue = DispatchQueue(label: "TileLauncher.dock-handoff", qos: .userInitiated)
    private lazy var polling: CompletionPoller<HandoffItem?> = {
        let queue = self.queue
        let polling = CompletionPoller<HandoffItem?>(interval: 0.4) { complete in
            queue.async {
                let item = Self.find().map { Self.item(title: $0.title, device: $0.device) }
                DispatchQueue.main.async { complete(item) }
            }
        }
        polling.onValue = { [weak self] item in
            guard let self, self.current != item else { return }
            self.current = item
            self.onChange?(item)
        }
        return polling
    }()
    private(set) var current: HandoffItem?
    var onChange: ((HandoffItem?) -> Void)?

    /// One preparation read; duplicate requests are skipped while a read is pending.
    func refresh() { polling.refresh() }
    /// Visible overlays read again 0.4 s after the previous read finishes.
    func startMonitoring() { polling.start() }
    func stopMonitoring() { polling.stop() }
    /// Press the Dock item for `item`, as a click on it would. The item is
    /// looked up again so a stale reference is never pressed.
    func press(_ item: HandoffItem, completion: @escaping (String?) -> Void) {
        queue.async {
            guard AXIsProcessTrusted() else {
                DispatchQueue.main.async { completion("접근성 권한이 필요합니다.") }; return
            }
            guard let found = Self.find(), found.title == item.appName else {
                DispatchQueue.main.async { completion("Handoff 항목이 사라졌습니다. 다른 기기에서 앱을 다시 열어 주세요.") }; return
            }
            let result = AXUIElementPerformAction(found.element, kAXPressAction as CFString)
            DispatchQueue.main.async { completion(result == .success ? nil : "Handoff를 열지 못했습니다.") }
        }
    }

    private static func find() -> (element: AXUIElement, title: String, device: String)? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        do {
            for list in try children(app) {
                // The Handoff item sits after the apps; search from the end.
                for element in try children(list).reversed() {
                    guard try string(element, kAXSubroleAttribute) == subrole else { continue }
                    return try (element, string(element, kAXTitleAttribute), string(element, "AXStatusLabel"))
                }
            }
        } catch { /* Stop this scan on a messaging failure; the next poll can retry. */ }
        return nil
    }
    private static func item(title: String, device: String) -> HandoffItem {
        HandoffItem(appName: title, appURL: applicationURL(named: title), device: device)
    }
    /// The Dock title is the app's display name: a running app, or a bundle of
    /// that name in the usual application folders. Unknown → generic icon.
    private static func applicationURL(named name: String) -> URL? {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }),
           let url = running.bundleURL { return url }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for folder in ["/Applications", "/System/Applications", "/Applications/Utilities",
                       "/System/Applications/Utilities", home + "/Applications"] {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".app")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
    private enum ReadError: Error { case cannotComplete }
    private static func attribute(_ element: AXUIElement, _ key: String) throws -> CFTypeRef? {
        // AX timeouts belong to each object, not its descendants. Bound list and
        // icon reads too, and restore the default before returning an AXPress target.
        AXUIElementSetMessagingTimeout(element, 0.3)
        defer { AXUIElementSetMessagingTimeout(element, 0) }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        if result == .cannotComplete { throw ReadError.cannotComplete }
        return result == .success ? value : nil
    }
    private static func children(_ element: AXUIElement) throws -> [AXUIElement] {
        try attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    private static func string(_ element: AXUIElement, _ key: String) throws -> String {
        try attribute(element, key) as? String ?? ""
    }
}
