import Foundation
import CoreGraphics

public struct PanelLayout: Equatable {
    public let frame: CGRect
    public let compact: Bool
    public let supported: Bool
    public var columns: Int {
        DeckGeometry(width: frame.width, compact: compact).windowColumns / 2
    }
    public var capacity: Int { columns * 2 }

    /// All coordinates are AppKit points, including negative monitor origins.
    public static func calculate(visibleFrame: CGRect, cursor: CGPoint) -> Self {
        let margin: CGFloat = 24
        let v = visibleFrame.insetBy(dx: min(margin, visibleFrame.width / 8),
                                     dy: min(margin, visibleFrame.height / 8))
        let upper = min(720, v.height, min(1040, v.width) / 1.2)
        var size: CGSize
        let compact = upper < 620 || v.width < 760
        if !compact {
            let height = min(max(v.height * 0.8, 620), upper)
            let lowerWidth = max(760, height * 1.2)
            let upperWidth = min(1040, v.width, height * 1.5)
            size = CGSize(width: min(max(height * 1.45, lowerWidth), upperWidth), height: height)
        } else {
            // In small work areas spacing changes; text is never scaled as an image.
            let ratio: CGFloat = v.height < 520 ? 1.5 : 1.25
            let height = min(v.height, v.width / ratio, 620)
            size = CGSize(width: height * ratio, height: height)
        }
        size.width = max(1, size.width.rounded(.down))
        size.height = max(1, size.height.rounded(.down))
        let x = min(max(cursor.x - size.width / 2, v.minX), v.maxX - size.width)
        let y = min(max(cursor.y - size.height / 2, v.minY), v.maxY - size.height)
        return Self(frame: CGRect(origin: CGPoint(x: x, y: y), size: size), compact: compact,
                    supported: size.width >= 512 && size.height >= 420)
    }

    public func windowLimit(manual: Int?, actual: Int, spans: [Int]? = nil) -> Int {
        let automatic = spans.map {
            TileArrangement.place(spans: $0, columns: columns * 2).prefix { $0.row < 2 }.count
        } ?? capacity
        return min(actual, manual.map { max(6, $0) } ?? max(6, automatic))
    }
}
