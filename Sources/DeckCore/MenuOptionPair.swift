import Foundation

/// A relationship witnessed from AXMenuItemPrimaryUIElement while a native
/// menu was open. Neither name similarity, adjacency nor an Option shortcut
/// alone is evidence of an alternate.
public struct MenuOptionPair: Equatable {
    public let primary: CapturedMenu
    public let alternate: MenuActionReference
    public init?(primary: CapturedMenu, alternate: MenuActionReference, primaryModifiers: Int, alternateModifiers: Int) {
        guard alternate.isValid, MenuActionReference(path: primary.identity.path, identifier: primary.axIdentifier).isValid, !MenuCapturePolicy.isAppleMenuPath(primary.identity.path),
              primary.identity.path.dropLast().elementsEqual(alternate.path.dropLast()),
              (primaryModifiers & 2) == 0, (alternateModifiers & 2) != 0,
              // NoCommand can differ on items with no key equivalent.
              (primaryModifiers & ~10) == (alternateModifiers & ~10),
              primary.identity.path != alternate.path || (primary.axIdentifier != nil && alternate.identifier != nil && primary.axIdentifier != alternate.identifier) else { return nil }
        self.primary = primary; self.alternate = alternate
    }
    public func matches(path: [String], identifier: String?) -> Bool {
        (path == primary.identity.path && identifier == primary.axIdentifier)
            || (path == alternate.path && identifier == alternate.identifier)
    }
    public func normalized(fromHelpSearch: Bool = false) -> CapturedMenu {
        CapturedMenu(appID: primary.identity.appID, appName: primary.appName, path: primary.identity.path,
                     shortcut: primary.shortcut, commandModifier: primary.commandModifier, modifiers: primary.modifiers,
                     shortcutKnown: primary.shortcutKnown, fromHelpSearch: fromHelpSearch,
                     axIdentifier: primary.axIdentifier, optionAction: alternate)
    }
}
