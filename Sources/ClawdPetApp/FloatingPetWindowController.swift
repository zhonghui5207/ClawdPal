import AppKit
import SwiftUI

final class FloatingPetWindowController {
    private enum DefaultsKey {
        static let windowFrame = "floatingPetWindowFrame"
    }

    private enum Layout {
        static let size = NSSize(width: 320, height: 260)
        static let margin: CGFloat = 40
        static let snapDistance: CGFloat = 120
    }

    private let window: NSPanel
    private var isAdjustingFrame = false

    init(appModel: AppModel) {
        let contentView = PetOverlayView(appModel: appModel)
        let hostingView = DraggableHostingView(rootView: contentView)
        hostingView.frame = NSRect(origin: .zero, size: Layout.size)

        window = NSPanel(
            contentRect: Self.initialFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.ignoresMouseEvents = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveFrame),
            name: NSWindow.didResizeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resetPosition),
            name: .clawdPetResetWindowPosition,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dragEnded),
            name: .clawdPetDragEnded,
            object: window
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        window.orderFrontRegardless()
    }

    @objc private func windowDidMove() {
        saveFrame()
    }

    @objc private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: DefaultsKey.windowFrame)
    }

    @objc private func dragEnded() {
        snapToNearestEdgeIfNeeded()
        saveFrame()
    }

    @objc private func resetPosition() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.windowFrame)
        window.setFrame(Self.defaultFrame(), display: true, animate: true)
        saveFrame()
    }

    private func snapToNearestEdgeIfNeeded() {
        guard !isAdjustingFrame else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let frame = window.frame
        let allowedFrame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: screenFrame.maxY - visibleFrame.minY
        )

        var target = frame
        let distances: [(CGFloat, Edge)] = [
            (abs(frame.minX - allowedFrame.minX), .left),
            (abs(allowedFrame.maxX - frame.maxX), .right),
            (abs(frame.minY - allowedFrame.minY), .bottom),
            (abs(allowedFrame.maxY - frame.maxY), .top)
        ]
        guard let nearest = distances.min(by: { $0.0 < $1.0 }),
              nearest.0 <= Layout.snapDistance else {
            clampWindowIntoAllowedFrame(allowedFrame)
            return
        }

        switch nearest.1 {
        case .left:
            target.origin.x = allowedFrame.minX
        case .right:
            target.origin.x = allowedFrame.maxX - frame.width
        case .bottom:
            target.origin.y = allowedFrame.minY
        case .top:
            target.origin.y = allowedFrame.maxY - frame.height
        }

        target.origin.x = min(max(target.origin.x, allowedFrame.minX), allowedFrame.maxX - target.width)
        target.origin.y = min(max(target.origin.y, allowedFrame.minY), allowedFrame.maxY - target.height)

        guard target != frame else { return }
        isAdjustingFrame = true
        window.setFrame(target, display: true, animate: true)
        isAdjustingFrame = false
    }

    private func clampWindowIntoAllowedFrame(_ allowedFrame: NSRect) {
        let frame = window.frame
        var target = frame
        target.origin.x = min(max(target.origin.x, allowedFrame.minX), allowedFrame.maxX - target.width)
        target.origin.y = min(max(target.origin.y, allowedFrame.minY), allowedFrame.maxY - target.height)
        guard target != frame else { return }

        isAdjustingFrame = true
        window.setFrame(target, display: true, animate: false)
        isAdjustingFrame = false
    }

    private static func initialFrame() -> NSRect {
        if let savedFrame = UserDefaults.standard.string(forKey: DefaultsKey.windowFrame) {
            let frame = NSRectFromString(savedFrame)
            if frame.width > 0, frame.height > 0 {
                return frame
            }
        }

        return defaultFrame()
    }

    private static func defaultFrame() -> NSRect {
        let size = Layout.size
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return NSRect(origin: NSPoint(x: 80, y: 140), size: size)
        }

        return NSRect(
            x: visibleFrame.maxX - size.width - Layout.margin,
            y: visibleFrame.minY + Layout.margin,
            width: size.width,
            height: size.height
        )
    }
}

private enum Edge {
    case left
    case right
    case bottom
    case top
}
