import Foundation
import CoreGraphics

public struct PanelLayout: Equatable {
    public let frame: CGRect
    public let compact: Bool
    public let supported: Bool
    public let scale: CGFloat
    public static let preferredScale: CGFloat = 1.3
    public init(frame: CGRect, compact: Bool, supported: Bool, scale: CGFloat = 1) {
        self.frame = frame; self.compact = compact; self.supported = supported
        self.scale = scale.isFinite ? max(1, min(Self.preferredScale, scale)) : 1
    }
    public var contentSize: CGSize {
        CGSize(width: frame.width / scale, height: frame.height / scale)
    }
    public var columns: Int {
        DeckGeometry(width: contentSize.width, compact: compact, scale: scale).windowColumns / 2
    }
    public var capacity: Int { columns * 3 }

    /// All coordinates are AppKit points, including negative monitor origins.
    public static func calculate(visibleFrame: CGRect, cursor: CGPoint, scale requestedScale: CGFloat = 1) -> Self {
        let margin: CGFloat = 24
        let v = visibleFrame.insetBy(dx: min(margin, visibleFrame.width / 8),
                                     dy: min(margin, visibleFrame.height / 8))
        if requestedScale.isFinite && requestedScale > 1 {
            let compact = v.height < 620 || v.width < 840
            let targetWidth = min(compact ? 850 : 1120, v.width)
            let scale = max(1, min(Self.preferredScale, requestedScale, v.width / max(1, targetWidth),
                                   v.height / (compact ? 420 : 620)))
            if scale > 1 {
                // Add back the legacy margins before calculating logical geometry;
                // the final physical window still stays 24pt inside the real screen.
                let logical = Self.calculate(visibleFrame: CGRect(x: 0, y: 0,
                    width: v.width / scale + 48, height: v.height / scale + 48), cursor: .zero)
                let size = CGSize(width: min(v.width, logical.frame.width * scale),
                                  height: min(v.height, logical.frame.height * scale))
                let x = min(max(cursor.x - size.width / 2, v.minX), v.maxX - size.width)
                let y = min(max(cursor.y - size.height / 2, v.minY), v.maxY - size.height)
                return Self(frame: CGRect(origin: CGPoint(x: x, y: y), size: size),
                            compact: logical.compact, supported: logical.supported, scale: scale)
            }
        }
        // A stable width lets the 1/2/4 module tiles keep readable labels.
        // The profile determines height, rather than an aspect ratio spacer.
        let compact = v.height < 620 || v.width < 840
        let width = min(compact ? 850 : 1120, v.width)
        var size = CGSize(width: width, height: min(840, v.height, width / 1.2))
        size.width = max(1, size.width.rounded(.down))
        size.height = max(1, size.height.rounded(.down))
        let x = min(max(cursor.x - size.width / 2, v.minX), v.maxX - size.width)
        let y = min(max(cursor.y - size.height / 2, v.minY), v.maxY - size.height)
        return Self(frame: CGRect(origin: CGPoint(x: x, y: y), size: size), compact: compact,
                    supported: size.width >= 512 && size.height >= 420)
    }

    /// Trim unused vertical space within the existing size/aspect limits.
    public func fittingContent(registeredCount: Int, workRows: CGFloat = 3.3) -> Self {
        let geometry = DeckGeometry(width: contentSize.width, compact: compact, scale: scale)
        let shelf = RegisteredGridGeometry(width: contentSize.width, scale: scale)
            .shelfHeight(count: registeredCount, maximumRows: compact ? 2 : 3)
        // Reserve native caption/icon line metrics plus rounding so a shelf row
        // never disappears for a one-point shortage at the viewport boundary.
        let workHeight = (geometry.viewport(rows: max(1, min(3.3, workRows))) + DeckSpacing.workHeader(scale: scale)).rounded(.up)
        let desired = workHeight + shelf
            + DeckSpacing.workToShelf(compact: compact) + DeckSpacing.chrome(compact: compact, scale: scale)
        let height = min(frame.height, desired.rounded(.up))
        return Self(frame: CGRect(x: frame.minX, y: frame.midY - height / 2, width: frame.width, height: height),
                    compact: compact, supported: supported, scale: scale)
    }

    /// Profile changes retain the top edge/dragged position and clamp to the screen.
    /// Rebuild from the screen ceiling so a smaller profile can grow again.
    public func refittingContent(registeredCount: Int, visibleFrame: CGRect, workRows: CGFloat = 3.3) -> Self {
        let ceiling = Self.calculate(visibleFrame: visibleFrame, cursor: CGPoint(x: frame.midX, y: frame.midY), scale: scale)
        let upper = Self(frame: CGRect(x: frame.minX, y: frame.minY, width: min(frame.width, ceiling.frame.width),
                                      height: ceiling.frame.height), compact: ceiling.compact, supported: ceiling.supported,
                         scale: ceiling.scale)
        let fitted = upper.fittingContent(registeredCount: registeredCount, workRows: workRows)
        let safe = visibleFrame.insetBy(dx: min(24, visibleFrame.width / 8), dy: min(24, visibleFrame.height / 8))
        let x = min(max(frame.minX, safe.minX), safe.maxX - fitted.frame.width)
        let y = min(max(frame.maxY - fitted.frame.height, safe.minY), safe.maxY - fitted.frame.height)
        return Self(frame: CGRect(x: x, y: y, width: fitted.frame.width, height: fitted.frame.height),
                    compact: fitted.compact, supported: fitted.supported, scale: fitted.scale)
    }

    /// The viewport never truncates automatic history.
    public func windowLimit(manual: Int?, actual: Int) -> Int {
        min(actual, manual.map { max(6, $0) } ?? actual)
    }
}
