import SwiftUI

/// R383: the footer of a regular (non-small) start-label menu tile with an
/// icon/resource/symbol/shortcut glyph — the saved parent menu path in a small
/// secondary line above the unchanged menu name. Display only: built from the
/// saved `MenuCommand.path`; nothing is guessed, queried or changed.
struct MenuTileCaption: View {
    /// Logical sizes; the tile multiplies them by the deck scale.
    enum Metrics {
        /// The existing footer name size (unchanged).
        static let nameSize: CGFloat = 12
        /// 75% of the name.
        static let pathSize: CGFloat = 9
        /// The existing footer inset.
        static let inset: CGFloat = 8
        /// The existing glyph bottom reserve for a one-line footer.
        static let glyphReserve: CGFloat = 22
        /// Added to `glyphReserve` when the parent path line is shown.
        static let pathLineReserve: CGFloat = 11
    }

    let title: String
    /// From `parentPath(of:)`: nil or a non-blank path. nil omits the line
    /// (and the caller's extra glyph reserve).
    let parentPath: String?
    let scale: CGFloat

    /// The saved parents (path without its last component), joined verbatim
    /// like the tooltip. nil when there are none or any parent is blank after
    /// trimming whitespace/newlines — such a path is not shown or reconstructed.
    static func parentPath(of path: [String]) -> String? {
        let parents = path.dropLast()
        guard !parents.isEmpty,
              parents.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
        return parents.joined(separator: " › ")
    }
    /// Bottom space the glyph keeps clear of this caption.
    static func glyphReserve(hasParentPath: Bool, scale: CGFloat) -> CGFloat {
        (Metrics.glyphReserve + (hasParentPath ? Metrics.pathLineReserve : 0)) * scale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let parentPath {
                // Middle truncation keeps both the root menu and the nearest parent.
                Text(parentPath)
                    .font(.system(size: Metrics.pathSize * scale, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: Metrics.nameSize * scale, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
    }
}
