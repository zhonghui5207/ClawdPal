import AppKit
import Foundation

struct TerminalJumpService {
    private let preferredBundleIDs = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "com.alacritty"
    ]

    func activateTerminal() -> String {
        let runningApplications = NSWorkspace.shared.runningApplications

        for bundleID in preferredBundleIDs {
            guard let application = runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
                continue
            }

            let didActivate = application.activate(options: [.activateIgnoringOtherApps])
            return didActivate ? "Jumped back to \(application.localizedName ?? "terminal")" : "Could not activate terminal"
        }

        return "No terminal app found"
    }
}
