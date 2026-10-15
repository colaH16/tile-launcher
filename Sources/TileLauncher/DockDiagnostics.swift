import AppKit
import ApplicationServices

/// R192 read-only probe of the Dock's accessibility items, to find out whether
/// a Handoff (Continuity) item is exposed and can be pressed. Never performs an
/// action, never changes Dock settings. Writes JSON lines to `output`.
enum DockDiagnostics {
    static func run(output: URL, seconds: TimeInterval) {
        guard AXIsProcessTrusted() else {
            fputs("Dock diagnostics need existing Accessibility trust; no prompt is shown.\n", stderr)
            exit(2)
        }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            fputs("Dock is not running.\n", stderr); exit(3)
        }
        FileManager.default.createFile(atPath: output.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: output) else { fputs("Cannot write output.\n", stderr); exit(4) }
        func write(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
            handle.write(data + Data("\n".utf8))
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let baseline = items(app)
        write(["event": "baseline", "count": baseline.count, "items": baseline.map(\.summary)])
        var known = Set(baseline.map(\.identity))
        print("Baseline: \(baseline.count) Dock items. Watching \(Int(seconds)) s for new items…")
        var end = Date().addingTimeInterval(seconds)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            for item in items(app) where !known.contains(item.identity) {
                known.insert(item.identity)
                write(["event": "appeared", "at": ISO8601DateFormatter().string(from: Date()), "item": item.detail])
                print("New Dock item: \(item.summary)")
                // Record a few more seconds of changes, then stop.
                end = min(end, Date().addingTimeInterval(5))
            }
            if Date() >= end {
                timer.invalidate()
                write(["event": "end"])
                try? handle.close()
                exit(0)
            }
        }
    }

    private struct Item {
        let element: AXUIElement
        let role: String, subrole: String, title: String
        var identity: String { "\(subrole)|\(title)|\(CFHash(element))" }
        var summary: [String: String] { ["role": role, "subrole": subrole, "title": title] }
        /// Every attribute name/value (as text) and every action name.
        var detail: [String: Any] {
            var names: CFArray?
            AXUIElementCopyAttributeNames(element, &names)
            var attributes: [String: String] = [:]
            for name in (names as? [String]) ?? [] {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { continue }
                attributes[name] = String(describing: value).prefix(300).description
            }
            var actions: CFArray?
            AXUIElementCopyActionNames(element, &actions)
            return ["summary": summary, "attributes": attributes, "actions": (actions as? [String]) ?? []]
        }
    }
    private static func items(_ app: AXUIElement) -> [Item] {
        children(app).flatMap { list in children(list).map { element in
            Item(element: element, role: string(element, kAXRoleAttribute), subrole: string(element, kAXSubroleAttribute),
                 title: string(element, kAXTitleAttribute))
        } }
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
