import AppKit

/// A tile lifting out of a stepped base, optically spaced for the menu bar.
enum BrandMark {
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            let base = NSBezierPath()
            base.move(to: NSPoint(x: 2, y: 6))
            base.line(to: NSPoint(x: 8, y: 6))
            base.line(to: NSPoint(x: 8, y: 10))
            base.line(to: NSPoint(x: 14, y: 10))
            base.line(to: NSPoint(x: 14, y: 16))
            base.line(to: NSPoint(x: 2, y: 16))
            base.close()
            base.fill()
            NSBezierPath(rect: NSRect(x: 10, y: 2, width: 6, height: 6)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppIdentity.name
        return image
    }
}
