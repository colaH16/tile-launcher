import AppKit
import ApplicationServices
import DeckCore

/// Value-only, bounded cache shared by observation and the explicit menu list.
/// A process identity prevents stale pairings after a target app restarts.
final class MenuOptionDiscovery {
    static let shared = MenuOptionDiscovery()
    private let lock = NSLock()
    private var entries: [String: (process: ProcessIdentity, pairs: [MenuOptionPair])] = [:]

    func pairs(for app: AppItem) -> [MenuOptionPair] {
        guard let process = ProcessIdentity.read(pid: app.pid) else { return [] }
        lock.lock(); defer { lock.unlock() }
        guard entries[app.id]?.process == process else { return [] }
        return entries[app.id]?.pairs ?? []
    }
    func remember(_ pairs: [MenuOptionPair], app: AppItem) {
        guard !pairs.isEmpty, let process = ProcessIdentity.read(pid: app.pid) else { return }
        lock.lock(); defer { lock.unlock() }
        var current = entries[app.id]?.process == process ? entries[app.id]!.pairs : []
        for pair in pairs {
            current.removeAll { $0.primary.identity == pair.primary.identity && $0.primary.axIdentifier == pair.primary.axIdentifier }
            current.append(pair)
        }
        if entries.count >= 64, entries[app.id] == nil { entries.removeAll() }
        entries[app.id] = (process, Array(current.suffix(256)))
    }
    func normalized(_ menu: CapturedMenu, app: AppItem) -> CapturedMenu {
        let matches = pairs(for: app).filter { $0.matches(path: menu.identity.path, identifier: menu.axIdentifier) }
        return matches.count == 1 ? matches[0].normalized(fromHelpSearch: menu.fromHelpSearch) : menu
    }

    /// Read only the opened siblings. Closed menus commonly report each item
    /// as its own primary, which must never erase a positive observed pair.
    static func read(opened node: AXUIElement, app: AppItem, budget: TimeInterval = 0.2) -> [MenuOptionPair] {
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        func value(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            AXUIElementSetMessagingTimeout(node, 0.025)
            var result: CFTypeRef?
            return AXUIElementCopyAttributeValue(node, key as CFString, &result) == .success ? result : nil
        }
        func element(_ node: AXUIElement, _ key: String) -> AXUIElement? {
            guard let raw = value(node, key), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
            return (raw as! AXUIElement)
        }
        var menu = node
        if value(menu, kAXRoleAttribute) as? String != kAXMenuRole {
            guard let child = (value(menu, kAXChildrenAttribute) as? [AXUIElement])?.first,
                  value(child, kAXRoleAttribute) as? String == kAXMenuRole else { return [] }
            menu = child
        }
        guard let visible = value(menu, kAXVisibleChildrenAttribute) as? [AXUIElement], !visible.isEmpty,
              let siblings = value(menu, kAXChildrenAttribute) as? [AXUIElement], siblings.count <= 100 else { return [] }
        var path: [String] = [], current: AXUIElement? = menu
        for _ in 0..<24 {
            guard let node = current else { return [] }
            let role = value(node, kAXRoleAttribute) as? String
            if role == kAXMenuBarRole { break }
            if role == kAXMenuItemRole || role == kAXMenuBarItemRole,
               let title = value(node, kAXTitleAttribute) as? String, !title.isEmpty { path.append(title) }
            current = element(node, kAXParentAttribute)
        }
        guard let root = current, value(root, kAXRoleAttribute) as? String == kAXMenuBarRole,
              !path.isEmpty else { return [] }
        path.reverse()
        // Exclude the Apple root structurally, not just by its displayed name.
        if let first = (value(root, kAXChildrenAttribute) as? [AXUIElement])?.first,
           let firstTitle = value(first, kAXTitleAttribute) as? String, firstTitle == path.first { return [] }
        func reference(_ item: AXUIElement) -> CapturedMenu? {
            var pid: pid_t = 0
            guard AXUIElementGetPid(item, &pid) == .success, pid == app.pid,
                  value(item, kAXRoleAttribute) as? String == kAXMenuItemRole,
                  let title = value(item, kAXTitleAttribute) as? String, !title.isEmpty,
                  let modifiers = value(item, kAXMenuItemCmdModifiersAttribute) as? Int else { return nil }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var rawChildren: CFTypeRef?
            let childCode = AXUIElementCopyAttributeValue(item, kAXChildrenAttribute as CFString, &rawChildren)
            guard childCode == .success || childCode == .noValue || childCode == .attributeUnsupported else { return nil }
            let children = rawChildren as? [AXUIElement] ?? []
            guard children.count <= 100, !children.contains(where: { value($0, kAXRoleAttribute) as? String == kAXMenuRole }) else { return nil }
            var actions: CFArray?
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  AXUIElementCopyActionNames(item, &actions) == .success,
                  (actions as? [String])?.contains(kAXPressAction) == true else { return nil }
            let key = value(item, kAXMenuItemCmdCharAttribute) as? String ?? ""
            return CapturedMenu(appID: app.id, appName: app.name, path: path + [title], shortcut: key,
                                modifiers: modifiers, shortcutKnown: true,
                                axIdentifier: value(item, kAXIdentifierAttribute) as? String)
        }
        var candidates: [MenuOptionPair] = []
        for alternate in siblings {
            guard let primary = element(alternate, kAXMenuItemPrimaryUIElementAttribute), !CFEqual(primary, alternate),
                  siblings.contains(where: { CFEqual($0, primary) }),
                  let a = reference(primary), let b = reference(alternate),
                  let pair = MenuOptionPair(primary: a, alternate: .init(path: b.identity.path, identifier: b.axIdentifier),
                                            primaryModifiers: a.modifiers, alternateModifiers: b.modifiers, alternateShortcut: b.shortcut) else { continue }
            candidates.append(pair)
        }
        // Several Option candidates for the same primary are ambiguous.
        return candidates.filter { pair in
            candidates.filter { $0.primary.identity == pair.primary.identity && $0.primary.axIdentifier == pair.primary.axIdentifier }.count == 1
        }
    }
}
