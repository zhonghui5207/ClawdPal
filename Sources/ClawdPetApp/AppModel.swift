import ClawdPetCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private struct TrackedSession {
        var event: AgentEvent
        var updatedAt: Date
    }

    @Published private(set) var mood: PetMood = .classic
    @Published private(set) var bubbleText: String = "Idle"
    @Published private(set) var lastEvent: AgentEvent?
    @Published private(set) var lastSource: String = "local"
    @Published private(set) var bridgeStatus: String = "Starting..."
    @Published private(set) var hookStatus: HookSetupService.Status = .disconnected
    @Published private(set) var activeSessionSummary: String = ""

    private let bridgeServer = BridgeServer()
    private let terminalJumpService = TerminalJumpService()
    private let hookSetupService = HookSetupService()
    private var completionTimer: Timer?
    private var activityRefreshTimer: Timer?
    private var sessionsBySource: [String: [String: TrackedSession]] = [:]

    func start() {
        refreshHookStatus()
        do {
            try bridgeServer.start { [weak self] envelope in
                Task { @MainActor in
                    self?.apply(envelope)
                }
            }
            bridgeStatus = "Listening on \(BridgePath.defaultSocketPath)"
        } catch {
            bridgeStatus = "Bridge error: \(error)"
            bubbleText = "Bridge offline"
        }
    }

    func stop() {
        completionTimer?.invalidate()
        activityRefreshTimer?.invalidate()
        bridgeServer.stop()
    }

    func setMood(_ mood: PetMood) {
        self.mood = mood
        self.bubbleText = mood.displayName
        self.lastSource = "manual"
        self.lastEvent = nil
    }

    func jumpBackToTerminal() {
        bubbleText = terminalJumpService.activateTerminal()
    }

    func resetWindowPosition() {
        NotificationCenter.default.post(name: .clawdPetResetWindowPosition, object: nil)
    }

    func installHooks() {
        runHookSetup(.installAll, pendingText: "Installing hooks...")
    }

    func uninstallHooks() {
        runHookSetup(.uninstallAll, pendingText: "Removing hooks...")
    }

    func connectOrRepairHooks() {
        let pendingText = hookStatus.isFullyConnected ? "Repairing hooks..." : "Connecting Claude and Codex..."
        runHookSetup(.installAll, pendingText: pendingText)
    }

    var panelSourceText: String {
        switch lastSource {
        case "manual":
            return "Manual"
        case "local":
            return "Local"
        default:
            return lastSource
        }
    }

    var panelEventText: String {
        guard let lastEvent else {
            return lastSource == "manual" ? "Manual Preview" : "None"
        }
        if let toolName = lastEvent.toolName, !toolName.isEmpty {
            return toolName
        }
        if let hookEventName = lastEvent.hookEventName, !hookEventName.isEmpty {
            return hookEventName
        }
        return lastEvent.kind.rawValue
    }

    var panelWorkingDirectoryText: String {
        guard let workingDirectory = lastEvent?.workingDirectory, !workingDirectory.isEmpty else {
            return "None"
        }
        return shortenedPath(workingDirectory, components: 2)
    }

    var panelSessionText: String {
        guard let sessionID = lastEvent?.sessionID, !sessionID.isEmpty else {
            return "None"
        }
        return shortenedSessionID(sessionID)
    }

    var panelBridgeStatusText: String {
        if bridgeStatus.hasPrefix("Listening on ") {
            return "Bridge connected"
        }
        if bridgeStatus.hasPrefix("Bridge error:") {
            return "Bridge offline"
        }
        return bridgeStatus
    }

    var panelBridgeStatusHelp: String {
        bridgeStatus
    }

    var hookSummaryText: String {
        if hookStatus.isFullyConnected {
            return "Claude and Codex connected"
        }
        if hookStatus.needsRepair {
            return "Hook config needs repair"
        }
        switch (hookStatus.claude, hookStatus.codex) {
        case (.connected, .disconnected):
            return "Codex not connected"
        case (.disconnected, .connected):
            return "Claude not connected"
        default:
            return "Connect Claude and Codex"
        }
    }

    var hookPrimaryActionTitle: String {
        hookStatus.isFullyConnected ? "Repair" : "Connect"
    }

    var hookPrimaryActionIcon: String {
        hookStatus.isFullyConnected ? "wrench.and.screwdriver" : "link.badge.plus"
    }

    var hookPrimaryActionHelp: String {
        hookStatus.isFullyConnected
            ? "Rewrite ClawdPet hook entries for Claude and Codex"
            : "Connect Claude and Codex activity to ClawdPet"
    }

    var claudeHookStateText: String {
        hookStateText(for: hookStatus.claude)
    }

    var codexHookStateText: String {
        hookStateText(for: hookStatus.codex)
    }

    var claudeHookHelp: String {
        hookStateHelp(prefix: "Claude", state: hookStatus.claude)
    }

    var codexHookHelp: String {
        hookStateHelp(prefix: "Codex", state: hookStatus.codex)
    }

    private func apply(_ envelope: BridgeEnvelope) {
        completionTimer?.invalidate()
        lastEvent = envelope.event
        lastSource = displaySource(envelope.source)
        updateTrackedSessions(for: envelope, source: lastSource)

        let presentation = PetMoodMapper.presentation(for: envelope.event)
        mood = presentation.mood
        bubbleText = "\(lastSource): \(presentation.bubbleText)"

        if envelope.event.kind == .completed {
            completionTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.mood = .classic
                    self?.bubbleText = "Idle"
                }
            }
        }
    }

    private func displaySource(_ source: String) -> String {
        switch source {
        case "claude-code", "claude":
            return "Claude"
        case "codex":
            return "Codex"
        default:
            return source
        }
    }

    private func runHookSetup(_ action: HookSetupService.Action, pendingText: String) {
        bubbleText = pendingText
        Task.detached { [hookSetupService] in
            do {
                let result = try hookSetupService.run(action)
                let status = hookSetupService.status()
                await MainActor.run {
                    self.hookStatus = status
                    self.bubbleText = result
                }
            } catch {
                let status = hookSetupService.status()
                await MainActor.run {
                    self.hookStatus = status
                    self.bubbleText = "Setup failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func refreshHookStatus() {
        Task.detached { [hookSetupService] in
            let status = hookSetupService.status()
            await MainActor.run {
                self.hookStatus = status
            }
        }
    }

    private func updateTrackedSessions(for envelope: BridgeEnvelope, source: String) {
        guard (source == "Claude" || source == "Codex"),
              let sessionID = envelope.event.sessionID,
              !sessionID.isEmpty else {
            refreshActiveSessions(now: envelope.receivedAt)
            return
        }

        var sourceSessions = sessionsBySource[source] ?? [:]
        sourceSessions[sessionID] = TrackedSession(event: envelope.event, updatedAt: envelope.receivedAt)
        sessionsBySource[source] = sourceSessions
        refreshActiveSessions(now: envelope.receivedAt)
        ensureActivityRefreshTimer()
    }

    private func refreshActiveSessions(now: Date = Date()) {
        pruneExpiredSessions(now: now)

        let claudeCount = sessionsBySource["Claude"]?.count ?? 0
        let codexCount = sessionsBySource["Codex"]?.count ?? 0

        var parts: [String] = []
        if claudeCount > 0 {
            parts.append(claudeCount == 1 ? "Claude" : "Claude \(claudeCount)")
        }
        if codexCount > 0 {
            parts.append(codexCount == 1 ? "Codex" : "Codex \(codexCount)")
        }

        activeSessionSummary = parts.joined(separator: " · ")

        if sessionsBySource.isEmpty {
            activityRefreshTimer?.invalidate()
            activityRefreshTimer = nil
        }
    }

    private func pruneExpiredSessions(now: Date) {
        for (source, sourceSessions) in sessionsBySource {
            let filtered = sourceSessions.filter { _, tracked in
                now.timeIntervalSince(tracked.updatedAt) < sessionLifetime(for: tracked.event)
            }
            if filtered.isEmpty {
                sessionsBySource.removeValue(forKey: source)
            } else {
                sessionsBySource[source] = filtered
            }
        }
    }

    private func ensureActivityRefreshTimer() {
        guard activityRefreshTimer == nil else { return }
        activityRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshActiveSessions()
            }
        }
    }

    private func shortenedPath(_ path: String, components count: Int) -> String {
        let pathComponents = path
            .split(separator: "/")
            .map(String.init)
        guard !pathComponents.isEmpty else {
            return path
        }
        return pathComponents.suffix(count).joined(separator: "/")
    }

    private func shortenedSessionID(_ sessionID: String) -> String {
        guard sessionID.count > 14 else {
            return sessionID
        }
        return "\(sessionID.prefix(8))...\(sessionID.suffix(4))"
    }

    private func hookStateText(for state: HookSetupService.ConnectionState) -> String {
        switch state {
        case .connected:
            return "Connected"
        case .disconnected:
            return "Not connected"
        case .broken:
            return "Needs repair"
        }
    }

    private func hookStateHelp(prefix: String, state: HookSetupService.ConnectionState) -> String {
        switch state {
        case .connected:
            return "\(prefix) hooks are installed."
        case .disconnected:
            return "\(prefix) hooks are not installed."
        case .broken(let message):
            return "\(prefix) hook config could not be read: \(message)"
        }
    }

    private func sessionLifetime(for event: AgentEvent) -> TimeInterval {
        switch event.kind {
        case .completed:
            return 4
        case .permissionRequest, .error:
            return 15
        case .idle, .thinking, .reading, .runningCommand, .editingCode, .unknown:
            return 30
        }
    }
}

extension Notification.Name {
    static let clawdPetDragEnded = Notification.Name("clawdPetDragEnded")
    static let clawdPetResetWindowPosition = Notification.Name("clawdPetResetWindowPosition")
    static let clawdPetSetPanelOpen = Notification.Name("clawdPetSetPanelOpen")
}
