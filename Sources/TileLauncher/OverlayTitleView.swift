import SwiftUI

/// Approved header proportions are independent of tile size.
struct OverlayTitleView: View {
    let iconURL: URL?
    let appName: String
    let windowName: String

    var body: some View {
        HStack(spacing: 6.9) {
            Icon(url: iconURL, size: 29.9)
                .environment(\.deckScale, 1)
            Text(appName).font(.system(size: 20.7, weight: .semibold))
                .lineLimit(1).truncationMode(.middle)
            if !windowName.isEmpty {
                Text("—").foregroundStyle(.secondary)
                Text(windowName).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.system(size: 14.95))
        .offset(y: 3)
        .help(windowName.isEmpty ? appName : "\(appName) — \(windowName)")
        .accessibilityElement(children: .combine)
    }
}
