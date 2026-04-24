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

    func jump(to workingDirectory: String?) -> String {
        guard let workingDirectory, !workingDirectory.isEmpty else {
            return activateTerminal()
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return "CWD not found"
        }

        for bundleID in preferredBundleIDs {
            if openTerminal(bundleID: bundleID, workingDirectory: workingDirectory) {
                return "Opened \(lastPathComponent(workingDirectory))"
            }
        }

        return activateTerminal()
    }

    private func openTerminal(bundleID: String, workingDirectory: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleID, workingDirectory]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func lastPathComponent(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
