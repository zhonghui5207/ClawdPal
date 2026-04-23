import AppKit
import SwiftUI

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        guard let window else {
            super.mouseDown(with: event)
            return
        }

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
                if didDrag {
                    NotificationCenter.default.post(name: .clawdPetDragEnded, object: window)
                } else {
                    super.mouseDown(with: event)
                }
                return
            default:
                break
            }
        }
    }
}
