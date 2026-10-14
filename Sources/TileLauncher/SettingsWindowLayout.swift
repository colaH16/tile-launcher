import AppKit
import SwiftUI

enum SettingsWindowLayout {
    static let defaultWidth: CGFloat = 580
    static let outerPadding = SettingsSpacing.paneInset

    @MainActor static func fittedContentSize(settings: SettingsStore, loginItem: LoginItemManager) -> CGSize {
        let content = GeneralSettingsContent(settings: settings, loginItem: loginItem,
                                             requestPermission: {}, openAppManagementSettings: {})
            .frame(width: defaultWidth - outerPadding * 2)
            .fixedSize(horizontal: false, vertical: true)
        let hosting = NSHostingView(rootView: content)
        return CGSize(width: defaultWidth, height: ceil(hosting.fittingSize.height) + outerPadding * 2)
    }

    @MainActor static func apply(to window: NSWindow, contentSize: CGSize, visibleFrame: NSRect?) {
        window.minSize = .zero
        window.setContentSize(contentSize)
        if let visibleFrame {
            let available = visibleFrame.insetBy(dx: 24, dy: 24)
            var frame = window.frame
            frame.size.width = min(frame.width, available.width)
            frame.size.height = min(frame.height, available.height)
            window.setFrame(frame, display: false)
        }
        window.minSize = NSSize(width: min(540, window.frame.width), height: min(660, window.frame.height))
    }
}
