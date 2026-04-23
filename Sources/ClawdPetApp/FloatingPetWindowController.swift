import AppKit
import SwiftUI

final class FloatingPetWindowController {
    private enum DefaultsKey {
        static let windowFrame = "floatingPetWindowFrame"
    }

    private enum Layout {
        static let width: CGFloat = 320
        static let compactHeight: CGFloat = 260
        static let fallbackExpandedHeight: CGFloat = 420
        static let margin: CGFloat = 40
    }

    private let window: NSPanel
    private var isAdjustingFrame = false

    init(appModel: AppModel) {
        let contentView = PetOverlayView(appModel: appModel)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: Layout.width, height: Layout.compactHeight)
        )

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
        window.isMovableByWindowBackground = false
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(setPanelOpen(_:)),
            name: .clawdPetSetPanelOpen,
            object: nil
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
        UserDefaults.standard.set(NSStringFromRect(Self.persistedFrame(for: window.frame)), forKey: DefaultsKey.windowFrame)
    }

    @objc private func dragEnded() {
        guard !isAdjustingFrame else { return }
        let clampedFrame = Self.clampedFrame(window.frame)
        guard clampedFrame != window.frame else {
            saveFrame()
            return
        }

        isAdjustingFrame = true
        window.setFrame(clampedFrame, display: true, animate: false)
        isAdjustingFrame = false
        saveFrame()
    }

    @objc private func resetPosition() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.windowFrame)
        window.setFrame(Self.defaultFrame(), display: true, animate: true)
        saveFrame()
    }

    @objc private func setPanelOpen(_ notification: Notification) {
        guard let isOpen = notification.userInfo?["isOpen"] as? Bool else { return }
        let preferredHeight = notification.userInfo?["preferredHeight"] as? CGFloat
        resizeWindow(isPanelOpen: isOpen, preferredHeight: preferredHeight)
    }

    private static func initialFrame() -> NSRect {
        if let savedFrame = UserDefaults.standard.string(forKey: DefaultsKey.windowFrame) {
            let frame = NSRectFromString(savedFrame)
            if frame.width > 0, frame.height > 0 {
                return clampedFrame(persistedFrame(for: frame))
            }
        }

        return defaultFrame()
    }

    private static func defaultFrame() -> NSRect {
        let size = NSSize(width: Layout.width, height: Layout.compactHeight)
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

    private static func clampedFrame(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main else {
            return defaultFrame()
        }

        let visibleFrame = screen.visibleFrame
        let screenFrame = screen.frame
        var target = frame
        target.origin.x = min(max(target.origin.x, visibleFrame.minX), visibleFrame.maxX - target.width)
        target.origin.y = min(max(target.origin.y, visibleFrame.minY), screenFrame.maxY - target.height)
        return target
    }

    private func resizeWindow(isPanelOpen: Bool, preferredHeight: CGFloat? = nil) {
        guard !isAdjustingFrame else { return }

        let targetHeight = isPanelOpen
            ? max(preferredHeight ?? Layout.fallbackExpandedHeight, Layout.fallbackExpandedHeight)
            : Layout.compactHeight
        guard abs(window.frame.height - targetHeight) > 0.5 else { return }

        var targetFrame = window.frame
        targetFrame.size.width = Layout.width
        targetFrame.size.height = targetHeight
        targetFrame = Self.clampedFrame(targetFrame)

        isAdjustingFrame = true
        window.setFrame(targetFrame, display: true, animate: true)
        isAdjustingFrame = false
        saveFrame()
    }

    private static func persistedFrame(for frame: NSRect) -> NSRect {
        var persisted = frame
        persisted.size.width = Layout.width
        persisted.size.height = Layout.compactHeight
        return persisted
    }
}
