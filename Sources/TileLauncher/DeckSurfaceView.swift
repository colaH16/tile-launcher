import AppKit
import SwiftUI

/// One outer silhouette for the glass, SwiftUI fill and any descendant effects.
/// NSGlassEffectView.cornerRadius shapes the glass, but does not clip its content.
final class DeckSurfaceView: NSView {
    static let cornerRadius: CGFloat = 28
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }
    private let silhouette = CAShapeLayer()

    init(content: NSView, frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.mask = silhouette
        // Keep the glass's own narrow dark edge outside the final silhouette.
        // The content stays at the original bounds; only the effect overscans.
        let glass = NSGlassEffectView(frame: bounds.insetBy(dx: -1, dy: -1))
        glass.style = .regular
        glass.cornerRadius = Self.cornerRadius + 1
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = content
        addSubview(glass)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -1),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 1),
            glass.topAnchor.constraint(equalTo: topAnchor, constant: -1),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 1),
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

    private func updateSilhouette() {
        // Only geometry changes affect the mask. Moving the panel must not animate
        // or regenerate a different shadow contour for every content refresh.
        guard silhouette.path == nil || silhouette.frame != bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.frame = bounds
        silhouette.path = Self.shape.path(in: CGRect(origin: .zero, size: bounds.size)).cgPath
        CATransaction.commit()
    }
}
