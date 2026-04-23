import ClawdPetCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    struct SessionDisplay: Identifiable, Equatable {
        var source: String
        var sessionID: String
        var taskTitle: String?
        var latestUserLine: String?
        var workspaceName: String
        var eventText: String
        var bubbleText: String
        var workingDirectoryText: String
        var shortSessionID: String
        var updatedAt: Date
        var priority: Int
        var kind: AgentEventKind

        var id: String { "\(source)-\(sessionID)" }
    }

    struct SourceSection: Identifiable, Equatable {
        var source: String
        var count: Int
        var headline: String
        var sessions: [SessionDisplay]

        var id: String { source }
        var sourceLabel: String { count > 1 ? "\(source) \(count)" : source }
    }

    private struct TrackedSession {
        var event: AgentEvent
        var updatedAt: Date
        var taskTitle: String?
        var latestUserLine: String?
    }

    @Published private(set) var mood: PetMood = .classic
    @Published private(set) var bubbleText: String = "Idle"
    @Published private(set) var lastEvent: AgentEvent?
    @Published private(set) var lastSource: String = "local"
    @Published private(set) var bridgeStatus: String = "Starting..."
    @Published private(set) var hookStatus: HookSetupService.Status = .disconnected
    @Published private(set) var activeSessionSummary: String = ""
    @Published private(set) var sourceSections: [SourceSection] = []
    @Published private(set) var focusedSession: SessionDisplay?

    private let bridgeServer = BridgeServer()
    private let terminalJumpService = TerminalJumpService()
    private let hookSetupService = HookSetupService()
    private let codexTranscriptMonitor = CodexTranscriptMonitor()
    private let transcriptPollQueue = DispatchQueue(label: "studio.lovexai.ClawdPet.codex-transcripts", qos: .utility)
    private var completionTimer: Timer?
    private var activityRefreshTimer: Timer?
    private var transcriptPollTimer: DispatchSourceTimer?
    private var sessionsBySource: [String: [String: TrackedSession]] = [:]
    private var transcriptSessionsBySource: [String: [String: TrackedSession]] = [:]

    func start() {
        refreshHookStatus()
        startTranscriptMonitoring()
        ensureActivityRefreshTimer()
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
        stopTranscriptMonitoring()
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
        if let focusedSession {
            return focusedSession.source
        }
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
        if let focusedSession {
            return focusedSession.eventText
        }
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
        if let focusedSession {
            return focusedSession.workingDirectoryText
        }
        guard let workingDirectory = lastEvent?.workingDirectory, !workingDirectory.isEmpty else {
            return "None"
        }
        return shortenedPath(workingDirectory, components: 2)
    }

    var panelSessionText: String {
        if let focusedSession {
            return focusedSession.shortSessionID
        }
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

    var panelTitleText: String? {
        if let title = focusedSession?.taskTitle, !title.isEmpty {
            return title
        }
        return nil
    }

    var panelLatestUserLineText: String? {
        if let line = focusedSession?.latestUserLine, !line.isEmpty {
            return line
        }
        if let message = cleanedMessage(lastEvent?.message, prefix: "Prompt:"), !message.isEmpty {
            return message
        }
        return nil
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
        if sourceSections.isEmpty {
            let presentation = PetMoodMapper.presentation(for: envelope.event)
            mood = presentation.mood
            bubbleText = "\(lastSource): \(presentation.bubbleText)"
        }

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
        sourceSessions[sessionID] = TrackedSession(
            event: envelope.event,
            updatedAt: envelope.receivedAt,
            taskTitle: nil,
            latestUserLine: cleanedMessage(envelope.event.message, prefix: "Prompt:")
        )
        sessionsBySource[source] = sourceSessions
        refreshActiveSessions(now: envelope.receivedAt)
        ensureActivityRefreshTimer()
    }

    private func refreshActiveSessions(now: Date = Date()) {
        pruneExpiredSessions(now: now)

        let combinedSessions = mergedSessions()

        sourceSections = buildSourceSections(from: combinedSessions)
        focusedSession = sourceSections
            .flatMap(\.sessions)
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .first

        updateActivityPresentation(now: now)

        var parts: [String] = []
        for section in sourceSections {
            parts.append(section.count == 1 ? section.source : "\(section.source) \(section.count)")
        }

        activeSessionSummary = parts.joined(separator: " · ")

    }

    private func mergedSessions() -> [String: [String: TrackedSession]] {
        var merged = sessionsBySource

        for (source, sourceSessions) in transcriptSessionsBySource {
            var mergedSourceSessions = merged[source] ?? [:]
            for (sessionID, tracked) in sourceSessions {
                if let existing = mergedSourceSessions[sessionID] {
                    if tracked.updatedAt >= existing.updatedAt {
                        mergedSourceSessions[sessionID] = tracked
                    }
                } else {
                    mergedSourceSessions[sessionID] = tracked
                }
            }
            merged[source] = mergedSourceSessions
        }

        return merged
    }

    private func pruneExpiredSessions(now: Date) {
        sessionsBySource = prunedSessions(from: sessionsBySource, now: now)
        transcriptSessionsBySource = prunedSessions(from: transcriptSessionsBySource, now: now)
    }

    private func prunedSessions(
        from sessions: [String: [String: TrackedSession]],
        now: Date
    ) -> [String: [String: TrackedSession]] {
        var pruned = sessions
        for (source, sourceSessions) in sessions {
            let filtered = sourceSessions.filter { _, tracked in
                now.timeIntervalSince(tracked.updatedAt) < sessionLifetime(for: tracked.event)
            }
            if filtered.isEmpty {
                pruned.removeValue(forKey: source)
            } else {
                pruned[source] = filtered
            }
        }
        return pruned
    }

    private func ensureActivityRefreshTimer() {
        guard activityRefreshTimer == nil else { return }
        activityRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshActiveSessions()
            }
        }
    }

    private func startTranscriptMonitoring() {
        guard transcriptPollTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: transcriptPollQueue)
        let monitor = codexTranscriptMonitor
        timer.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(400))
        timer.setEventHandler { [weak self] in
            let snapshots = monitor.snapshots(now: Date())
            Task { @MainActor [weak self] in
                self?.applyTranscriptSnapshots(snapshots)
            }
        }
        transcriptPollTimer = timer
        timer.resume()
    }

    private func stopTranscriptMonitoring() {
        transcriptPollTimer?.cancel()
        transcriptPollTimer = nil
    }

    private func applyTranscriptSnapshots(_ snapshots: [CodexTranscriptSnapshot]) {
        var nextCodexSessions: [String: TrackedSession] = [:]
        for snapshot in snapshots {
            nextCodexSessions[snapshot.sessionID] = TrackedSession(
                event: snapshot.event,
                updatedAt: snapshot.updatedAt,
                taskTitle: snapshot.taskTitle,
                latestUserLine: snapshot.latestUserLine
            )
        }

        if nextCodexSessions.isEmpty {
            transcriptSessionsBySource.removeValue(forKey: "Codex")
        } else {
            transcriptSessionsBySource["Codex"] = nextCodexSessions
        }

        refreshActiveSessions()
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

    private func buildSourceSections(from sessions: [String: [String: TrackedSession]]) -> [SourceSection] {
        ["Claude", "Codex"].compactMap { source in
            guard let sourceSessions = sessions[source], !sourceSessions.isEmpty else {
                return nil
            }

            let displays = sourceSessions.map { sessionID, tracked in
                sessionDisplay(
                    source: source,
                    sessionID: sessionID,
                    tracked: tracked
                )
            }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.updatedAt > rhs.updatedAt
            }

            return SourceSection(
                source: source,
                count: displays.count,
                headline: displays.first?.taskTitle ?? displays.first?.eventText ?? "Watching",
                sessions: displays
            )
        }
    }

    private func sessionDisplay(source: String, sessionID: String, tracked: TrackedSession) -> SessionDisplay {
        SessionDisplay(
            source: source,
            sessionID: sessionID,
            taskTitle: tracked.taskTitle,
            latestUserLine: tracked.latestUserLine,
            workspaceName: workspaceName(for: tracked.event.workingDirectory),
            eventText: eventText(for: tracked.event),
            bubbleText: bubbleSummary(for: source, event: tracked.event),
            workingDirectoryText: workingDirectoryText(for: tracked.event.workingDirectory),
            shortSessionID: shortenedSessionID(sessionID),
            updatedAt: tracked.updatedAt,
            priority: eventPriority(for: tracked.event.kind),
            kind: tracked.event.kind
        )
    }

    private func workspaceName(for path: String?) -> String {
        guard let path, !path.isEmpty else {
            return "No cwd"
        }
        return shortenedPath(path, components: 1)
    }

    private func workingDirectoryText(for path: String?) -> String {
        guard let path, !path.isEmpty else {
            return "None"
        }
        return shortenedPath(path, components: 2)
    }

    private func eventText(for event: AgentEvent) -> String {
        humanizedSummary(for: event)
    }

    private func eventPriority(for kind: AgentEventKind) -> Int {
        switch kind {
        case .permissionRequest, .error:
            return 5
        case .editingCode, .runningCommand:
            return 4
        case .reading, .thinking:
            return 3
        case .completed:
            return 2
        case .idle, .unknown:
            return 1
        }
    }

    private func updateActivityPresentation(now: Date) {
        guard !sourceSections.isEmpty else { return }
        if let focusedSession {
            mood = moodForFocusedSession(focusedSession)
        }

        let summaries = sourceSections.compactMap { section in
            section.sessions.first.map { bubbleText(for: $0, sourceCount: sourceSections.count, now: now) }
        }
        guard !summaries.isEmpty else { return }
        if summaries.count == 1 {
            bubbleText = summaries[0]
            return
        }

        let rotationIndex = Int(now.timeIntervalSinceReferenceDate / 3) % summaries.count
        bubbleText = summaries[rotationIndex]
    }

    private func moodForFocusedSession(_ session: SessionDisplay) -> PetMood {
        switch session.kind {
        case .idle:
            return .classic
        case .thinking:
            return .hoodie
        case .reading:
            return .explorer
        case .runningCommand, .error:
            return .street
        case .editingCode:
            return .suit
        case .permissionRequest:
            return .hoodie
        case .completed:
            return .pajama
        case .unknown:
            return .classic
        }
    }

    private func bubbleSummary(for source: String, event: AgentEvent) -> String {
        "\(source): \(humanizedSummary(for: event))"
    }

    private func bubbleText(for session: SessionDisplay, sourceCount: Int, now: Date) -> String {
        if shouldPreferTaskTitle(for: session, now: now), let taskTitle = session.taskTitle, !taskTitle.isEmpty {
            return sourceCount > 1 ? "\(session.source): \(taskTitle)" : taskTitle
        }
        return sourceCount > 1 ? session.bubbleText : bubbleTextWithoutSourcePrefix(session.bubbleText, source: session.source)
    }

    private func shouldPreferTaskTitle(for session: SessionDisplay, now: Date) -> Bool {
        guard session.taskTitle != nil else { return false }

        let age = now.timeIntervalSince(session.updatedAt)
        switch session.kind {
        case .permissionRequest, .error:
            return false
        case .completed:
            return age > 4
        case .reading, .runningCommand, .editingCode, .thinking:
            return age > 6
        case .idle, .unknown:
            return true
        }
    }

    private func bubbleTextWithoutSourcePrefix(_ text: String, source: String) -> String {
        let prefix = "\(source): "
        guard text.hasPrefix(prefix) else {
            return text
        }
        return String(text.dropFirst(prefix.count))
    }

    private func humanizedSummary(for event: AgentEvent) -> String {
        switch event.kind {
        case .thinking:
            if let prompt = cleanedMessage(event.message, prefix: "Prompt:") {
                return clipped(prompt)
            }
            return "Thinking"
        case .reading:
            if let file = cleanedMessage(event.message, prefix: "File:") {
                return "Read \(file)"
            }
            if let pattern = cleanedMessage(event.message, prefix: "Search:") {
                return "Search \(clipped(pattern, limit: 24))"
            }
            return "Reading"
        case .runningCommand:
            if let command = cleanedMessage(event.message, prefix: "Command:") {
                return "Bash \(clipped(command, limit: 24))"
            }
            return "Running"
        case .editingCode:
            if let file = cleanedMessage(event.message, prefix: "File:") {
                return "Edit \(file)"
            }
            if let editing = cleanedMessage(event.message, prefix: "Editing:") {
                return "Edit \(clipped(editing, limit: 24))"
            }
            return "Editing"
        case .permissionRequest:
            return "Permission request"
        case .error:
            if cleanedMessage(event.message, prefix: "Permission denied") != nil {
                return "Permission denied"
            }
            if let message = event.message, !message.isEmpty {
                return clipped(strippedKnownPrefix(message), limit: 24)
            }
            return "Tool failed"
        case .completed:
            return "Done"
        case .idle:
            return "Idle"
        case .unknown:
            if let hookEventName = event.hookEventName, !hookEventName.isEmpty {
                return hookEventName
            }
            return "Watching"
        }
    }

    private func cleanedMessage(_ message: String?, prefix: String) -> String? {
        guard let message, message.hasPrefix(prefix) else {
            return nil
        }
        return message.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func strippedKnownPrefix(_ message: String) -> String {
        let prefixes = ["Prompt:", "Command:", "File:", "Search:", "Editing:"]
        for prefix in prefixes where message.hasPrefix(prefix) {
            return String(message.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return message
    }

    private func clipped(_ value: String, limit: Int = 28) -> String {
        guard value.count > limit else {
            return value
        }
        return "\(value.prefix(limit - 1))..."
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
