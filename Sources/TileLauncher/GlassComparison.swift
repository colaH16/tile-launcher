import AppKit
import SwiftUI
import DeckCore

/// R183 on-screen comparison of the overlay glass. Synthetic content only:
/// no instance lock, global monitors, status item or user window inventory.
/// Esc or Q closes; it also quits by itself after the given seconds.
@MainActor enum GlassComparison {
    private static var panels: [NSPanel] = []
    private static var monitor: Any?
    private static var fixtures: [PreviewFixture] = []

    static func show(seconds: TimeInterval) {
        guard let screen = NSScreen.main else { return }
        let variants: [(DeckSurfaceView.GlassVariant, Bool, String)] = [
            (.current, true, "A · 현재 (가장자리 마스크 + 0.28 색)"),
            (.unmasked, false, "C · 마스크 제거 + 색 레이어 제거"),
            (.clear, false, "D · C + clear 스타일")
        ]
        let gap: CGFloat = 12
        let visible = screen.visibleFrame
        let width = (visible.width - gap * CGFloat(variants.count + 1)) / CGFloat(variants.count)
        for (index, (variant, tint, label)) in variants.enumerated() {
            let fixture = PreviewFixture(theme: .glass, registeredCount: 18, menuComparison: true, realisticSample: true)
            var layout = PanelLayout.calculate(visibleFrame: CGRect(x: 0, y: 0, width: width + 48, height: visible.height),
                                               cursor: .zero)
            fixture.content.snapshot.layout = layout
            layout = layout.fittingContent(registeredCount: fixture.settings.pins.count,
                                           workRows: fixture.content.snapshot.workRows())
            fixture.content.snapshot.layout = layout
            fixture.presentation.profile = fixture.settings.activeProfile
            fixture.presentation.pin()
            fixtures.append(fixture)
            let view = DeckView(content: fixture.content, settings: fixture.settings, browser: fixture.browser,
                presentation: fixture.presentation, selectApp: { _ in }, selectPin: { _ in }, selectMenu: { _, _, _ in },
                changeProfile: { _ in }, cycleProfile: { _ in }, selectWindow: { _ in }, openURL: { _ in },
                openInFinder: { _ in }, openTrash: {}, showSettings: { _ in }, requestPermission: {}, pinOverlay: {},
                backdropTint: tint, dismiss: { NSApp.terminate(nil) })
                .overlay(alignment: .bottom) {
                    Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.75), in: Capsule()).padding(.bottom, 34)
                }
            let hosting = NSHostingView(rootView: view)
            let frame = CGRect(x: visible.minX + gap + CGFloat(index) * (width + gap),
                               y: visible.midY - layout.frame.height / 2,
                               width: min(width, layout.frame.width), height: layout.frame.height)
            let surface = DeckSurfaceView(content: hosting, frame: CGRect(origin: .zero, size: frame.size), variant: variant)
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.contentView = surface
            panel.setFrame(frame, display: false)
            surface.layoutSubtreeIfNeeded()
            panel.invalidateShadow()
            panel.orderFrontRegardless()
            panels.append(panel)
            print("\(variant.rawValue) windowNumber=\(panel.windowNumber)")
        }
        fflush(stdout)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 || event.charactersIgnoringModifiers == "q" { NSApp.terminate(nil) }
            return event
        }
        panels.last?.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
    }
}
