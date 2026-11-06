#if TILE_LAUNCHER_DIAGNOSTICS || TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
import ApplicationServices
import CoreFoundation
import DeckCore
import Foundation

/// The production role reader and traversal, with injected CF values and child
/// lists. Runs in both flag-off debug and diagnostic builds; no AX queries.
enum MenuHelpCatalogPolicyValidation {
    private enum Result: Equatable { case value(MenuCatalogTraversal.Role), unavailable, failure }
    private static func result(_ read: MenuCatalogTraversal.Read<MenuCatalogTraversal.Role>) -> Result {
        switch read {
        case .value(let role): return .value(role)
        case .unavailable: return .unavailable
        case .failure: return .failure
        }
    }

    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else {
                throw NSError(domain: "TileLauncher.MenuHelpCatalogPolicyValidation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        let accepted: [(String, MenuCatalogTraversal.Role)] = [
            (kAXMenuBarItemRole, .menuBarItem), (kAXMenuItemRole, .menuItem), (kAXMenuRole, .container),
            (kAXGroupRole, .structuralGroup), (kAXButtonRole, .controlLeaf)]
        var cases: [(AXError, CFTypeRef?, Result)] = accepted.map { (.success, $0.0 as NSString, .value($0.1)) }
        cases += [(.attributeUnsupported, kAXGroupRole as NSString, .unavailable),
                  (.noValue, kAXButtonRole as NSString, .unavailable),
                  (.cannotComplete, kAXGroupRole as NSString, .failure), (.success, nil, .failure),
                  (.success, NSNumber(value: 7), .failure), (.success, kCFBooleanTrue, .failure),
                  (.success, NSArray(), .failure), (.success, kAXImageRole as NSString, .failure),
                  (.success, "private custom role fixture" as NSString, .failure)]
        for (error, value, expected) in cases {
            var calls = 0
            let plain = MenuHelpCatalogRoleRead.read { calls += 1; return (error, value) }
            try check(result(plain) == expected && calls == 1,
                      "Shared production role mapping must retain one provider read and its exact outcome")
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            var diagnosticCalls = 0, reports = 0
            let diagnostic = MenuHelpRoleRead.read({ diagnosticCalls += 1; return (error, value) }, report: { _ in reports += 1 })
            try check(result(diagnostic) == result(plain) && diagnosticCalls == 1,
                      "Diagnostic ON and production role readers must share decisions and query counts")
            switch expected {
            case .value: try check(reports == 0, "Accepted Group/Button raw roles must not trigger unsupported-role probes")
            case .failure, .unavailable: try check(reports == 1, "A rejected role reports exactly once")
            }
            #endif
        }
        for (_, role) in accepted {
            try check(MenuHelpChildrenPolicy.isUnsupportedLeaf(.attributeUnsupported, menuItem: role == .menuItem)
                      == (role == .menuItem), "Existing unsupported-child compatibility applies only to known MenuItem")
            try check(!MenuHelpChildrenPolicy.isUnsupportedLeaf(.noValue, menuItem: role == .menuItem)
                      && !MenuHelpChildrenPolicy.isUnsupportedLeaf(.cannotComplete, menuItem: role == .menuItem),
                      "Neither Groups nor Buttons become proven leaves after missing/error children")
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            var reads: [String] = []
            let unsupported = MenuHelpChildrenRead.read(leafAllowed: role == .menuItem, limit: 100,
                count: { reads.append("count"); return (.attributeUnsupported, 0) },
                canCopy: { reads.append("canCopy"); return true },
                copy: { _ in reads.append("copy"); return (.success, nil) }, report: { _ in })
            if role == .menuItem {
                guard case .value(let children) = unsupported, children.isEmpty else {
                    throw NSError(domain: "TileLauncher.MenuHelpCatalogPolicyValidation", code: 2)
                }
            } else {
                guard case .unavailable = unsupported else {
                    throw NSError(domain: "TileLauncher.MenuHelpCatalogPolicyValidation", code: 3)
                }
            }
            try check(reads == ["count"], "Unsupported child reads must stop before copy, without granting new-role leaf compatibility")
            #endif
        }

        // The observed shape exercises the actual role adapter in ordinary
        // builds too: no opt-in or diagnostic helper participates in acceptance.
        let roles: [Int: String] = [1: kAXMenuBarItemRole, 2: kAXMenuRole, 3: kAXGroupRole, 4: kAXGroupRole,
                                    5: kAXButtonRole, 6: kAXButtonRole, 7: kAXButtonRole, 8: kAXButtonRole,
                                    9: kAXButtonRole, 10: kAXButtonRole, 11: kAXButtonRole, 12: kAXMenuItemRole]
        let children = [1: [2], 2: [3, 12], 3: [4], 4: Array(5...11)]
        var roleReads = 0, childReads = 0
        var titleReads: [Int] = []
        let outcome = MenuCatalogTraversal.scan(roots: { .value([.init(node: 1)]) },
            role: { node in
                MenuHelpCatalogRoleRead.read { roleReads += 1; return (.success, roles[node]! as NSString) }
            }, title: { node in
                titleReads.append(node)
                return .value(node == 1 ? "File" : "TSV…")
            }, children: { node in childReads += 1; return .value(children[node] ?? []) },
            hasTime: { true }, isCancelled: { false })
        guard case .complete(let entries, let stats) = outcome else {
            throw NSError(domain: "TileLauncher.MenuHelpCatalogPolicyValidation", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Production mapping rejected the observed valid Group/Button structure"])
        }
        try check(entries.map(\.path) == [["File", "TSV…"]] && entries.map(\.node) == [12],
                  "Only real MenuItem leaves may be emitted, after all structural descendants are checked")
        try check(roleReads == 12 && childReads == 12 && stats.nodes == 12 && titleReads == [1, 12],
                  "New roles share the normal traversal, without Group/Button titles, extra queries or a second scan")

        print("Menu Help catalog policy: shared native role mapping and observed Group/Button traversal preserve candidate scope and single-read behavior with no AX queries.")
    }
}
#endif
