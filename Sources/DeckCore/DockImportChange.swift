import Foundation

/// A preview is only a value: it cannot change the profile or its saved data.
/// Apply/undo require the expected list, preserving any intervening user edits.
public struct DockImportChange: Identifiable, Equatable {
    public let id = UUID()
    public let profileID: String
    public let profileName: String
    public let before: [PinnedItem]
    public let after: [PinnedItem]
    public let skipped: Int
    public init(profile: LauncherProfile, imported: DockImportResult) {
        profileID = profile.id; profileName = profile.name
        before = profile.items
        after = DockImport.merge(imported.items, into: profile.items)
        skipped = imported.skipped
    }
    public var hasChanges: Bool { before != after }
    public var addedIDs: Set<String> { Set(after.map(\.id)).subtracting(before.map(\.id)) }
    public func applying(to profile: LauncherProfile) -> [PinnedItem]? {
        profile.id == profileID && profile.items == before ? after : nil
    }
    public func undoing(in profile: LauncherProfile) -> [PinnedItem]? {
        profile.id == profileID && profile.items == after ? before : nil
    }
}
