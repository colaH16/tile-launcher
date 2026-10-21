import AppKit
import SwiftUI

/// One outer silhouette for the glass, SwiftUI fill and any descendant effects.
/// NSGlassEffectView.cornerRadius shapes the glass, but does not clip its content.
final class DeckSurfaceView: NSView {
    /// Comparison only (R183): `current` is the shipped surface. `unmasked`
    /// lets the glass draw its own rim without the overscan/mask, and `clear`
    /// additionally uses the more transparent glass style.
    enum GlassVariant: String, CaseIterable { case current, unmasked, clear }
    static let cornerRadius: CGFloat = 28
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }
    private let silhouette = CAShapeLayer()
    private let glass: NSGlassEffectView

    private let variant: GlassVariant

    init(content: NSView, frame: CGRect, variant: GlassVariant = .current) {
        self.variant = variant
        let overscan: CGFloat = variant == .current ? 1 : 0
        glass = NSGlassEffectView(frame: CGRect(origin: .zero, size: frame.size).insetBy(dx: -overscan, dy: -overscan))
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        // Keep the glass's own narrow dark edge outside the final silhouette.
        // The content stays at the original bounds; only the effect overscans.
        if variant == .current { layer?.mask = silhouette }
        glass.style = variant == .clear ? .clear : .regular
        glass.cornerRadius = Self.cornerRadius + overscan
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = content
        addSubview(glass)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -overscan),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: overscan),
            glass.topAnchor.constraint(equalTo: topAnchor, constant: -overscan),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: overscan),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateSilhouette()
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        silhouette.contentsScale = window?.backingScaleFactor ?? 1
    }

    override func layout() {
        super.layout()
        updateSilhouette()
    }

    func setBackgroundInteractive(_ enabled: Bool) {
        if #available(macOS 27.0, *) {
            let allowed = enabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            if glass.effectIsInteractive != allowed { glass.effectIsInteractive = allowed }
        }
    }

    private func updateSilhouette() {
        // Only geometry changes affect the mask. Moving the panel must not animate
        // or regenerate a different shadow contour for every content refresh.
        guard variant == .current, silhouette.path == nil || silhouette.frame != bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.frame = bounds
        silhouette.path = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .path(in: CGRect(origin: .zero, size: bounds.size)).cgPath
        CATransaction.commit()
    }
}
