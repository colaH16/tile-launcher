import SwiftUI

enum SettingsSpacing {
    static let paneInset: CGFloat = 16
    static let sectionGap: CGFloat = 16
    static let footerGap: CGFloat = 12
}

struct SettingsPaneInsets: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, SettingsSpacing.paneInset)
    }
}
