import AppKit
import SwiftUI

/// The title area starts a native window drag; tiles and header buttons remain
/// separate click targets. No position is persisted beyond this presentation.
struct OverlayDragHandle: NSViewRepresentable {
    let enabled: Bool

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { view.enabled = enabled }

    final class DragView: NSView {
        var enabled = false {
            didSet { updateWindow() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateWindow()
        }

        private func updateWindow() {
            window?.isMovable = enabled
            // Only this explicit title region starts a drag, not the tile grid.
            window?.isMovableByWindowBackground = false
            toolTip = enabled ? "제목을 드래그하여 오버레이 이동" : nil
            setAccessibilityElement(enabled)
            setAccessibilityRole(.group)
            setAccessibilityLabel("오버레이 이동 영역")
            setAccessibilityHelp(enabled ? "고정된 창의 제목 영역을 드래그하여 이동합니다." : nil)
        }

        override func mouseDown(with event: NSEvent) {
            guard enabled, let window else { return }
            window.performDrag(with: event)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { enabled }
    }
}
