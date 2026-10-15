import AppKit
import ApplicationServices

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
    private(set) var current: HandoffItem?
    var onChange: ((HandoffItem?) -> Void)?

    /// Re-read the Dock; `onChange` fires on the main thread only when the item changes.
    func refresh() {
        queue.async { [weak self] in
            let item = Self.find().map { Self.item(title: $0.title, device: $0.device) }
            DispatchQueue.main.async {
                guard let self, self.current != item else { return }
                self.current = item
                self.onChange?(item)
            }
        }
    }
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
        AXUIElementSetMessagingTimeout(app, 0.3)
        for list in children(app) {
            // The Handoff item sits after the apps; search from the end.
            for element in children(list).reversed() where string(element, kAXSubroleAttribute) == subrole {
                return (element, string(element, kAXTitleAttribute), string(element, "AXStatusLabel"))
            }
        }
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
    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
    private static func string(_ element: AXUIElement, _ key: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
}
