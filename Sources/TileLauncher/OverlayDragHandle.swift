import AppKit
import SwiftUI

/// The header background starts a native window drag; tiles and header buttons remain
/// separate click targets. No position is persisted beyond this presentation.
struct OverlayDragHandle: NSViewRepresentable {
    let enabled: Bool
    var excludedRects: [CGRect] = []

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        view.excludedRects = excludedRects
        view.enabled = enabled
    }

    final class DragView: NSView {
        var excludedRects: [CGRect] = []
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            guard enabled, !isHidden, bounds.contains(local),
                  !excludedRects.contains(where: { $0.contains(local) }) else { return nil }
            return self
        }

        var enabled = false {
            didSet { updateWindow() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateWindow()
        }

        private func updateWindow() {
            window?.isMovable = enabled
            // Only this header starts a drag, not the tile grid. Actual control
            // bounds come from SwiftUI so padding and gaps remain draggable.
            window?.isMovableByWindowBackground = false
            toolTip = enabled ? "상단의 빈 곳을 드래그하여 오버레이 이동" : nil
            setAccessibilityElement(enabled)
            setAccessibilityRole(.group)
            setAccessibilityLabel("오버레이 이동 영역")
            setAccessibilityHelp(enabled ? "고정된 창의 상단에서 버튼을 제외한 빈 곳이나 제목을 드래그하여 이동합니다." : nil)
        }

        override func mouseDown(with event: NSEvent) {
            guard enabled, let window else { return }
            window.performDrag(with: event)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { enabled }
    }
}
