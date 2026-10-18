import AppKit
import ApplicationServices
import DeckCore

/// A local settings-list annotation, never a deletion or synchronized field.
enum MenuAvailabilityReader {
    @MainActor static func missing(_ commands: [MenuCommand]) async -> Set<UUID> {
        guard let appID = commands.first?.appID else { return [] }
        // An app that is not installed on this Mac has none of its menus.
        let installed = appID.hasPrefix("/") ? FileManager.default.fileExists(atPath: appID)
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID) != nil
        if !installed { return Set(commands.map(\.id)) }
        // Otherwise only a complete accessibility read of the running app can
        // prove a menu is missing; any error or a closed app stays unknown.
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == appID }) else { return [] }
        let pid = app.processIdentifier
        return await Task.detached(priority: .utility) {
            let application = AXUIElementCreateApplication(pid)
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            var failed = false
            func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
                guard ProcessInfo.processInfo.systemUptime < deadline else { failed = true; return nil }
                AXUIElementSetMessagingTimeout(element, 0.08)
                var value: CFTypeRef?
                let code = AXUIElementCopyAttributeValue(element, key as CFString, &value)
                if code != .success && !(key == kAXTitleAttribute && code == .noValue) { failed = true }
                return code == .success ? value : nil
            }
            guard let raw = read(application, kAXMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID(), !failed else { return Set<UUID>() }
            let bar = unsafeBitCast(raw, to: AXUIElement.self)
            guard let roots = read(bar, kAXChildrenAttribute) as? [AXUIElement], roots.count > 1, !failed else { return Set<UUID>() }
            var missing = Set<UUID>()
            for command in commands {
                failed = false
                let paths = MenuPathMatch.paths(command)
                guard !paths.isEmpty else { continue }
                let resolution = MenuPathResolver.resolve(paths: paths, root: bar, children: { element in
                    guard let children = read(element, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
                    var result: [AXUIElement] = []
                    for child in children {
                        if read(child, kAXRoleAttribute) as? String == kAXMenuRole {
                            result += read(child, kAXChildrenAttribute) as? [AXUIElement] ?? []
                        } else { result.append(child) }
                    }
                    return result
                }, title: { read($0, kAXTitleAttribute) as? String }, equal: { CFEqual($0, $1) })
                if case .missing = resolution, !failed { missing.insert(command.id) }
            }
            return missing
        }.value
    }
}
