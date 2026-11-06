import ApplicationServices
import DeckCore

/// The deferred Help catalog's single AXRole read and role mapping, shared by
/// the flag-off and diagnostic builds so they cannot drift. One `copy` call;
/// attributeUnsupported/noValue is unavailable, any other error or a missing /
/// non-string value fails, and only five AX roles are accepted:
/// AXMenuBarItem, AXMenuItem, AXMenu (container), AXGroup (structural group)
/// and AXButton (control leaf). Placement of groups/controls is validated by
/// `MenuCatalogTraversal.scan` against the actual parent.
enum MenuHelpCatalogRoleRead {
    enum Result: Equatable {
        case accepted(MenuCatalogTraversal.Role)
        /// attributeUnsupported or noValue.
        case unavailable(AXError)
        case error(AXError)
        case missingValue
        case nonString
        /// A string role outside the five; kept only for in-process classification.
        case unsupported(String)
    }
    static func role(forRaw raw: String) -> MenuCatalogTraversal.Role? {
        switch raw {
        case kAXMenuBarItemRole: return .menuBarItem
        case kAXMenuItemRole: return .menuItem
        case kAXMenuRole: return .container
        case kAXGroupRole: return .structuralGroup
        case kAXButtonRole: return .controlLeaf
        default: return nil
        }
    }
    static func classify(error: AXError, value: CFTypeRef?) -> Result {
        if error == .attributeUnsupported || error == .noValue { return .unavailable(error) }
        guard error == .success else { return .error(error) }
        guard let value else { return .missingValue }
        guard let raw = value as? String else { return .nonString }
        guard let role = role(forRaw: raw) else { return .unsupported(raw) }
        return .accepted(role)
    }
    static func read(_ copy: () -> (AXError, CFTypeRef?)) -> MenuCatalogTraversal.Read<MenuCatalogTraversal.Role> {
        let (error, value) = copy()
        return outcome(classify(error: error, value: value))
    }
    static func outcome(_ result: Result) -> MenuCatalogTraversal.Read<MenuCatalogTraversal.Role> {
        switch result {
        case .accepted(let role): return .value(role)
        case .unavailable: return .unavailable
        case .error, .missingValue, .nonString, .unsupported: return .failure
        }
    }
}
