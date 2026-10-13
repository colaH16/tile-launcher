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
        let glass = NSGlassEffectView(frame: bounds)
        glass.style = .regular
        glass.cornerRadius = Self.cornerRadius
        glass.autoresizingMask = [.width, .height]
        glass.contentView = content
        addSubview(glass)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            content.topAnchor.constraint(equalTo: glass.topAnchor),
            content.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
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
