/// Stable app groups over an existing window MRU list. Every window remains
/// individually addressable; the active group moves first without sorting titles.
public enum GroupedRecentWindows {
    public static func order<App: Hashable>(apps: [App], activeApp: App?) -> [Int] {
        var keys: [App] = []
        var groups: [App: [Int]] = [:]
        for (index, app) in apps.enumerated() {
            if groups[app] == nil { keys.append(app) }
            groups[app, default: []].append(index)
        }
        if let activeApp, let position = keys.firstIndex(of: activeApp) {
            keys.remove(at: position)
            keys.insert(activeApp, at: 0)
        }
        return keys.flatMap { groups[$0, default: []] }
    }

    public static func sizes<App: Equatable>(apps: [App], applications: [Bool],
                                             desktops: [WindowDesktop], activeApp: App?) -> [RecentTileSize] {
        precondition(apps.count == applications.count && apps.count == desktops.count)
        let representative = apps.indices.first {
            activeApp == apps[$0] && !applications[$0] && desktops[$0] == .current
        }
        return apps.indices.map { index in
            if applications[index] { return .application }
            if index == representative { return .wide }
            return desktops[index] == .current ? .square : .application
        }
    }
}
