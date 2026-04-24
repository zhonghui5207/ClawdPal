import AppKit
import ClawdPalCore
import SwiftUI

@main
struct ClawdPalApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appModel = AppModel()
    private var windowController: FloatingPetWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = FloatingPetWindowController(appModel: appModel)
        windowController = controller
        controller.show()
        appModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel.stop()
    }
}
