import AppKit
import SwiftUI

struct PetInteractionView: NSViewRepresentable {
    var onClick: () -> Void
    var onPointerMove: (CGSize) -> Void = { _ in }
    var onPointerExit: () -> Void = {}
    var onPressChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        view.onClick = onClick
        view.onPointerMove = onPointerMove
        view.onPointerExit = onPointerExit
        view.onPressChanged = onPressChanged
        return view
    }

    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        nsView.onClick = onClick
        nsView.onPointerMove = onPointerMove
        nsView.onPointerExit = onPointerExit
        nsView.onPressChanged = onPressChanged
    }
}

final class InteractionNSView: NSView {
    var onClick: (() -> Void)?
    var onPointerMove: ((CGSize) -> Void)?
    var onPointerExit: (() -> Void)?
    var onPressChanged: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
                owner: self
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        publishPointerOffset(from: event)
    }

    override func mouseEntered(with event: NSEvent) {
        publishPointerOffset(from: event)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExit?()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            super.mouseDown(with: event)
            return
        }
        onPressChanged?(true)

        let originalWindowFrame = window.frame
        let originalMouseLocation = NSEvent.mouseLocation
        var didDrag = false

        while true {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else {
                break
            }

            switch nextEvent.type {
            case .leftMouseDragged:
                let currentMouseLocation = NSEvent.mouseLocation
                let deltaX = currentMouseLocation.x - originalMouseLocation.x
                let deltaY = currentMouseLocation.y - originalMouseLocation.y

                if abs(deltaX) > 3 || abs(deltaY) > 3 {
                    didDrag = true
                }

                guard didDrag else { continue }

                let newOrigin = NSPoint(
                    x: originalWindowFrame.origin.x + deltaX,
                    y: originalWindowFrame.origin.y + deltaY
                )
                window.setFrameOrigin(newOrigin)
            case .leftMouseUp:
                onPressChanged?(false)
                if didDrag {
                    NotificationCenter.default.post(name: .clawdPalDragEnded, object: window)
                } else {
                    onClick?()
                }
                return
            default:
                break
            }
        }
        onPressChanged?(false)
    }

    private func publishPointerOffset(from event: NSEvent) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let location = convert(event.locationInWindow, from: nil)
        let x = ((location.x - bounds.midX) / max(bounds.width / 2, 1)).clamped(to: -1...1)
        let y = ((location.y - bounds.midY) / max(bounds.height / 2, 1)).clamped(to: -1...1)
        onPointerMove?(CGSize(width: x, height: y))
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
