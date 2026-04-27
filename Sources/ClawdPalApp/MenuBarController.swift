import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let appModel: AppModel
    private weak var windowController: FloatingPetWindowController?

    init(appModel: AppModel, windowController: FloatingPetWindowController) {
        self.appModel = appModel
        self.windowController = windowController
        statusItem = NSStatusBar.system.statusItem(withLength: 26)
        super.init()

        if let button = statusItem.button {
            button.image = ClawdPalMenuIcon.image()
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let visibilityTitle = windowController?.isVisible == true ? "Hide ClawdPal" : "Show ClawdPal"
        menu.addItem(item(visibilityTitle, action: #selector(toggleVisibility)))
        menu.addItem(.separator())

        menu.addItem(disabledItem("Mode"))
        for mode in PresentationMode.allCases {
            let modeItem = item(mode.displayName, action: #selector(selectPresentationMode(_:)))
            modeItem.representedObject = mode.rawValue
            modeItem.state = appModel.presentationMode == mode ? .on : .off
            menu.addItem(modeItem)
        }

        menu.addItem(.separator())
        menu.addItem(item("Hook Manager", action: #selector(openHookManager)))
        menu.addItem(item("Reset Position", action: #selector(resetPosition)))

        let archiveItem = item("Archive All", action: #selector(archiveAll))
        archiveItem.isEnabled = !appModel.sourceSections.isEmpty
        menu.addItem(archiveItem)

        menu.addItem(.separator())
        menu.addItem(disabledItem(appModel.panelBridgeStatusText))
        menu.addItem(disabledItem("Claude: \(appModel.claudeHookStateText)"))
        menu.addItem(disabledItem("Codex: \(appModel.codexHookStateText)"))

        menu.addItem(.separator())
        menu.addItem(item("Quit ClawdPal", action: #selector(quit)))
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        return menuItem
    }

    @objc private func toggleVisibility() {
        windowController?.toggleVisibility()
    }

    @objc private func selectPresentationMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = PresentationMode(rawValue: rawValue) else {
            return
        }
        appModel.setPresentationMode(mode)
    }

    @objc private func openHookManager() {
        windowController?.show()
        appModel.showHookManager()
    }

    @objc private func resetPosition() {
        windowController?.show()
        appModel.resetWindowPosition()
    }

    @objc private func archiveAll() {
        appModel.archiveAllVisibleSessions()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private enum ClawdPalMenuIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let lineWidth: CGFloat = 2.2

        let head = NSBezierPath(roundedRect: NSRect(x: 3.8, y: 3.1, width: 10.4, height: 11.8), xRadius: 1.5, yRadius: 1.5)
        head.lineWidth = lineWidth
        head.lineJoinStyle = .round
        head.stroke()

        let leftEar = NSBezierPath()
        leftEar.lineWidth = lineWidth
        leftEar.lineJoinStyle = .round
        leftEar.lineCapStyle = .round
        leftEar.move(to: NSPoint(x: 3.7, y: 10.0))
        leftEar.line(to: NSPoint(x: 1.0, y: 10.0))
        leftEar.line(to: NSPoint(x: 1.0, y: 7.3))
        leftEar.line(to: NSPoint(x: 3.7, y: 7.3))
        leftEar.stroke()

        let rightEar = NSBezierPath()
        rightEar.lineWidth = lineWidth
        rightEar.lineJoinStyle = .round
        rightEar.lineCapStyle = .round
        rightEar.move(to: NSPoint(x: 14.3, y: 10.0))
        rightEar.line(to: NSPoint(x: 17.0, y: 10.0))
        rightEar.line(to: NSPoint(x: 17.0, y: 7.3))
        rightEar.line(to: NSPoint(x: 14.3, y: 7.3))
        rightEar.stroke()

        NSBezierPath(roundedRect: NSRect(x: 6.4, y: 7.0, width: 1.5, height: 4.4), xRadius: 0.5, yRadius: 0.5).fill()
        NSBezierPath(roundedRect: NSRect(x: 10.2, y: 7.0, width: 1.5, height: 4.4), xRadius: 0.5, yRadius: 0.5).fill()

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "ClawdPal"
        return image
    }
}
