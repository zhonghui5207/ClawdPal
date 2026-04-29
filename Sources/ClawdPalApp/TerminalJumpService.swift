import AppKit
import ApplicationServices
import Darwin
import Foundation

struct TerminalWindowContext: Equatable {
    var bundleID: String
    var processIdentifier: pid_t
    var windowTitle: String
    var windowIndex: Int
    var sessionID: String?
    var workingDirectory: String?
}

enum TerminalJumpFallback {
    case activateApplication
    case none
}

struct TerminalJumpService {
    private static let processTimeout: TimeInterval = 5

    private let preferredBundleIDs = [
        "com.mitchellh.ghostty",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.apple.Terminal",
        "net.kovidgoyal.kitty",
        "com.alacritty"
    ]

    private let codexBundleID = "com.openai.codex"

    func activateTerminal() -> String {
        for bundleID in preferredRunningTerminalBundleIDs() {
            guard activateApplication(bundleID: bundleID) else {
                continue
            }
            return "Jumped back to \(applicationName(for: bundleID))"
        }

        return "No terminal app found"
    }

    func jump(
        to workingDirectory: String?,
        sessionID: String? = nil,
        windowContext: TerminalWindowContext? = nil,
        fallback: TerminalJumpFallback = .activateApplication
    ) -> String {
        if let windowContext {
            guard AXIsProcessTrusted() else {
                return "Enable Terminal Access"
            }
            if raiseTerminalWindow(matching: windowContext) {
                return "Jumped back to \(applicationName(for: windowContext.bundleID))"
            }
        }

        if let sessionID, !sessionID.isEmpty {
            guard AXIsProcessTrusted() else {
                return "Enable Terminal Access"
            }
            if raiseTerminalWindow(sessionID: sessionID, workingDirectory: workingDirectory) {
                return "Jumped back to terminal window"
            }
        }

        if fallback == .none {
            return "Session window not found"
        }

        guard let workingDirectory, !workingDirectory.isEmpty else {
            return activateTerminal()
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return "CWD not found"
        }

        if let runningTerminalBundleID = preferredRunningTerminalBundleIDs().first,
           activateApplication(bundleID: runningTerminalBundleID) {
            return "Jumped back to \(applicationName(for: runningTerminalBundleID))"
        }

        for bundleID in preferredRunningOrInstalledTerminalBundleIDs() {
            if openTerminal(bundleID: bundleID, workingDirectory: workingDirectory) {
                return "Opened \(lastPathComponent(workingDirectory)) in \(applicationName(for: bundleID))"
            }
        }

        return activateTerminal()
    }

    func currentTerminalWindowContext(sessionID: String?, workingDirectory: String?) -> TerminalWindowContext? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let windows = terminalWindows()
        guard !windows.isEmpty else {
            return nil
        }

        if let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           preferredBundleIDs.contains(frontmostBundleID),
           let focusedWindow = windows.first(where: { $0.bundleID == frontmostBundleID && $0.isFocused }) {
            return focusedWindow.context(sessionID: sessionID, workingDirectory: workingDirectory)
        }

        if let focusedWindow = windows.first(where: \.isFocused) {
            return focusedWindow.context(sessionID: sessionID, workingDirectory: workingDirectory)
        }

        return bestMatchingWindow(
            from: windows,
            sessionID: sessionID,
            workingDirectory: workingDirectory
        )?.context(sessionID: sessionID, workingDirectory: workingDirectory)
    }

    func activateCodex() -> String {
        if activateApplication(bundleID: codexBundleID) {
            return "Opened Codex"
        }

        if let application = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == codexBundleID }) {
            let didActivate = application.activate(options: [.activateIgnoringOtherApps])
            return didActivate ? "Opened Codex" : "Could not activate Codex"
        }

        return "Codex app not found"
    }

    private func preferredRunningOrInstalledTerminalBundleIDs() -> [String] {
        let runningPreferred = preferredRunningTerminalBundleIDs()
        let remainingPreferred = preferredBundleIDs.filter { !runningPreferred.contains($0) }
        return runningPreferred + remainingPreferred
    }

    private func preferredRunningTerminalBundleIDs() -> [String] {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return preferredBundleIDs.filter { runningBundleIDs.contains($0) }
    }

    private func openTerminal(bundleID: String, workingDirectory: String) -> Bool {
        runProcess(executable: "/usr/bin/open", arguments: ["-b", bundleID, workingDirectory])
    }

    private func activateApplication(bundleID: String) -> Bool {
        runProcess(executable: "/usr/bin/open", arguments: ["-b", bundleID])
    }

    private func runProcess(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let semaphore = DispatchSemaphore(value: 0)
        var terminated = false
        var success = false

        process.terminationHandler = { proc in
            success = proc.terminationStatus == 0
            terminated = true
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return false
        }

        let result = semaphore.wait(timeout: .now() + Self.processTimeout)
        if result == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 1)
            if !terminated {
                kill(process.processIdentifier, SIGKILL)
            }
            return false
        }

        return success
    }

    private func raiseTerminalWindow(matching context: TerminalWindowContext) -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        let windows = terminalWindows(bundleID: context.bundleID)
        guard let window = bestMatchingWindow(from: windows, context: context) else {
            return false
        }

        return raiseTerminalWindow(window)
    }

    private func raiseTerminalWindow(
        sessionID: String,
        workingDirectory: String?
    ) -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        let windows = terminalWindows()
        guard let window = bestMatchingWindow(
            from: windows,
            sessionID: sessionID,
            workingDirectory: workingDirectory
        ) else {
            return false
        }

        return raiseTerminalWindow(window)
    }

    private func raiseTerminalWindow(_ window: TerminalWindowCandidate) -> Bool {
        NSWorkspace.shared.runningApplications
            .first { $0.processIdentifier == window.processIdentifier }?
            .activate(options: [.activateIgnoringOtherApps])

        let didRaise = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) == .success
        _ = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(window.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        return didRaise
    }

    private func terminalWindows(bundleID preferredBundleID: String? = nil) -> [TerminalWindowCandidate] {
        let runningApplications = NSWorkspace.shared.runningApplications
            .filter { application in
                guard let bundleID = application.bundleIdentifier else {
                    return false
                }
                guard preferredBundleIDs.contains(bundleID) else {
                    return false
                }
                if let preferredBundleID {
                    return bundleID == preferredBundleID
                }
                return true
            }

        return runningApplications.flatMap { application -> [TerminalWindowCandidate] in
            guard let bundleID = application.bundleIdentifier else {
                return []
            }

            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = axArrayAttribute(kAXWindowsAttribute as CFString, from: appElement) else {
                return []
            }

            return windows.enumerated().compactMap { index, element in
                let title = axStringAttribute(kAXTitleAttribute as CFString, from: element) ?? ""
                return TerminalWindowCandidate(
                    bundleID: bundleID,
                    processIdentifier: application.processIdentifier,
                    title: title,
                    index: index,
                    isFocused: axBoolAttribute(kAXFocusedAttribute as CFString, from: element) ?? false,
                    element: element
                )
            }
        }
    }

    private func bestMatchingWindow(
        from windows: [TerminalWindowCandidate],
        context: TerminalWindowContext
    ) -> TerminalWindowCandidate? {
        windows
            .map { window in
                (window: window, score: matchScore(window, context: context))
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.window.isFocused && !rhs.window.isFocused
            }
            .first?
            .window
    }

    private func bestMatchingWindow(
        from windows: [TerminalWindowCandidate],
        sessionID: String?,
        workingDirectory: String?
    ) -> TerminalWindowCandidate? {
        windows
            .map { window in
                (window: window, score: matchScore(window, sessionID: sessionID, workingDirectory: workingDirectory))
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in lhs.score > rhs.score }
            .first?
            .window
    }

    private func matchScore(_ window: TerminalWindowCandidate, context: TerminalWindowContext) -> Int {
        var score = 0

        if window.processIdentifier == context.processIdentifier {
            score += 30
        }
        if window.title == context.windowTitle {
            score += 100
        }
        if window.index == context.windowIndex {
            score += 10
        }

        score += matchScore(
            window,
            sessionID: context.sessionID,
            workingDirectory: context.workingDirectory
        )

        return score
    }

    private func matchScore(
        _ window: TerminalWindowCandidate,
        sessionID: String?,
        workingDirectory: String?
    ) -> Int {
        var score = 0
        let title = window.title

        if let sessionID, !sessionID.isEmpty {
            let sessionScore = sessionTitleScore(title: title, sessionID: sessionID)
            guard sessionScore > 0 else {
                return 0
            }
            score += sessionScore
        }

        if let workingDirectory, !workingDirectory.isEmpty {
            if title.contains(workingDirectory) {
                score += 25
            } else if title.contains(lastPathComponent(workingDirectory)) {
                score += 15
            }
        }

        return score
    }

    private func sessionTitleScore(title: String, sessionID: String) -> Int {
        if title.contains(sessionID) {
            return 80
        }
        if title.contains(String(sessionID.prefix(18))) {
            return 60
        }
        if title.contains(String(sessionID.prefix(13))) {
            return 40
        }
        return 0
    }

    private func axArrayAttribute(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private func axStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func axBoolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private func lastPathComponent(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func applicationName(for bundleID: String) -> String {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?
            .localizedName ?? terminalDisplayName(for: bundleID)
    }

    private func terminalDisplayName(for bundleID: String) -> String {
        switch bundleID {
        case "com.mitchellh.ghostty":
            return "Ghostty"
        case "com.googlecode.iterm2":
            return "iTerm"
        case "dev.warp.Warp-Stable", "dev.warp.Warp":
            return "Warp"
        case "com.apple.Terminal":
            return "Terminal"
        case "net.kovidgoyal.kitty":
            return "Kitty"
        case "com.alacritty":
            return "Alacritty"
        default:
            return "terminal"
        }
    }
}

private struct TerminalWindowCandidate {
    var bundleID: String
    var processIdentifier: pid_t
    var title: String
    var index: Int
    var isFocused: Bool
    var element: AXUIElement

    func context(sessionID: String?, workingDirectory: String?) -> TerminalWindowContext {
        TerminalWindowContext(
            bundleID: bundleID,
            processIdentifier: processIdentifier,
            windowTitle: title,
            windowIndex: index,
            sessionID: sessionID,
            workingDirectory: workingDirectory
        )
    }
}
