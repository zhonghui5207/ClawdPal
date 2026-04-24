import ClawdPalCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    struct SessionDisplay: Identifiable, Equatable {
        var source: String
        var sessionID: String
        var taskTitle: String?
        var latestUserLine: String?
        var subagents: [SubagentDisplay]
        var workspaceName: String
        var eventText: String
        var bubbleText: String
        var workingDirectory: String?
        var workingDirectoryText: String
        var terminalWindowContext: TerminalWindowContext?
        var shortSessionID: String
        var updatedAt: Date
        var priority: Int
        var kind: AgentEventKind
        var isActive: Bool

        var id: String { "\(source)-\(sessionID)" }
        var hasActiveSubagents: Bool { !subagents.isEmpty }
        var activeSubagentCount: Int { subagents.count }
    }

    struct SubagentDisplay: Identifiable, Equatable {
        var id: String
        var name: String
        var taskTitle: String
        var actionText: String
        var durationText: String
    }

    struct SourceSection: Identifiable, Equatable {
        var source: String
        var count: Int
        var headline: String
        var sessions: [SessionDisplay]

        var id: String { source }
        var sourceLabel: String { count > 1 ? "\(source) \(count)" : source }
    }

    enum HookTargetID: String, CaseIterable, Identifiable {
        case claude
        case codex

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .claude:
                return "Claude Code"
            case .codex:
                return "Codex"
            }
        }
    }

    struct HookTargetDisplay: Identifiable, Equatable {
        var id: HookTargetID
        var name: String
        var stateText: String
        var helpText: String
        var isConnected: Bool
        var needsRepair: Bool
        var primaryActionTitle: String
        var primaryActionIcon: String
    }

    private struct TrackedSession {
        var event: AgentEvent
        var updatedAt: Date
        var taskTitle: String?
        var latestUserLine: String?
        var terminalWindowContext: TerminalWindowContext?
        var pendingSubagent: PendingSubagent?
        var subagents: [String: TrackedSubagent] = [:]
    }

    private struct PendingSubagent {
        var name: String
        var taskTitle: String
        var createdAt: Date
    }

    private struct TrackedSubagent {
        var id: String
        var name: String
        var taskTitle: String
        var actionText: String
        var latestKind: AgentEventKind
        var startedAt: Date
        var updatedAt: Date
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
    @Published var isHookManagerOpen: Bool = false

    private let bridgeServer = BridgeServer()
    private let terminalJumpService = TerminalJumpService()
    private let hookSetupService = HookSetupService()
    private let codexTranscriptMonitor = CodexTranscriptMonitor()
    private let transcriptPollQueue = DispatchQueue(label: "studio.lovexai.ClawdPal.codex-transcripts", qos: .utility)
    private let focusHoldDuration: TimeInterval = 5
    private let subagentLifetime: TimeInterval = 30 * 60
    private let completedSubagentLifetime: TimeInterval = 8
    private var completionTimer: Timer?
    private var activityRefreshTimer: Timer?
    private var transcriptPollTimer: DispatchSourceTimer?
    private var sessionsBySource: [String: [String: TrackedSession]] = [:]
    private var transcriptSessionsBySource: [String: [String: TrackedSession]] = [:]
    private var codexSubagentParents: [String: String] = [:]
    private var archivedSessions: [String: Date] = [:]
    private var focusedSessionID: String?
    private var focusedSessionChangedAt: Date = .distantPast

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
        if let focusedSession, shouldOpenCodexClient(for: focusedSession) {
            bubbleText = terminalJumpService.activateCodex()
            return
        }

        bubbleText = terminalJumpService.jump(
            to: focusedSession?.workingDirectory ?? lastEvent?.workingDirectory,
            sessionID: focusedSession?.sessionID ?? lastEvent?.sessionID,
            windowContext: focusedSession?.terminalWindowContext
        )
    }

    func jumpToSession(_ session: SessionDisplay) {
        if shouldOpenCodexClient(for: session) {
            bubbleText = terminalJumpService.activateCodex()
            return
        }

        bubbleText = terminalJumpService.jump(
            to: session.workingDirectory,
            sessionID: session.sessionID,
            windowContext: session.terminalWindowContext,
            fallback: .none
        )
    }

    func openCodexClient() {
        bubbleText = terminalJumpService.activateCodex()
    }

    private func shouldOpenCodexClient(for session: SessionDisplay) -> Bool {
        session.source == "Codex"
    }

    func resetWindowPosition() {
        NotificationCenter.default.post(name: .clawdPalResetWindowPosition, object: nil)
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

    func showHookManager() {
        isHookManagerOpen = true
        refreshHookStatus()
    }

    func hideHookManager() {
        isHookManagerOpen = false
    }

    func runPrimaryHookAction(for target: HookTargetID) {
        switch target {
        case .claude:
            runHookSetup(.installClaude, pendingText: hookPendingText(for: target))
        case .codex:
            runHookSetup(.installCodex, pendingText: hookPendingText(for: target))
        }
    }

    func disconnectHook(_ target: HookTargetID) {
        switch target {
        case .claude:
            runHookSetup(.uninstallClaude, pendingText: "Disconnecting Claude Code...")
        case .codex:
            runHookSetup(.uninstallCodex, pendingText: "Disconnecting Codex...")
        }
    }

    func archiveSession(_ session: SessionDisplay) {
        archivedSessions[session.id] = Date()
        if focusedSessionID == session.id {
            focusedSessionID = nil
        }
        refreshActiveSessions()
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
            ? "Rewrite ClawdPal hook entries for Claude and Codex"
            : "Connect Claude and Codex activity to ClawdPal"
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

    var hookTargets: [HookTargetDisplay] {
        HookTargetID.allCases.map { target in
            let state = hookState(for: target)
            return HookTargetDisplay(
                id: target,
                name: target.displayName,
                stateText: hookStateText(for: state),
                helpText: hookStateHelp(prefix: target.displayName, state: state),
                isConnected: state == .connected,
                needsRepair: hookNeedsRepair(state),
                primaryActionTitle: hookPrimaryActionTitle(for: state),
                primaryActionIcon: hookPrimaryActionIcon(for: state)
            )
        }
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

        if envelope.event.kind == .completed,
           !hasActiveSubagents(source: lastSource, sessionID: envelope.event.sessionID) {
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

    private func hookState(for target: HookTargetID) -> HookSetupService.ConnectionState {
        switch target {
        case .claude:
            return hookStatus.claude
        case .codex:
            return hookStatus.codex
        }
    }

    private func hookNeedsRepair(_ state: HookSetupService.ConnectionState) -> Bool {
        if case .broken = state {
            return true
        }
        return false
    }

    private func hookPrimaryActionTitle(for state: HookSetupService.ConnectionState) -> String {
        switch state {
        case .connected:
            return "Reinstall"
        case .disconnected:
            return "Connect"
        case .broken:
            return "Fix"
        }
    }

    private func hookPrimaryActionIcon(for state: HookSetupService.ConnectionState) -> String {
        switch state {
        case .connected:
            return "arrow.clockwise"
        case .disconnected:
            return "link.badge.plus"
        case .broken:
            return "wrench.and.screwdriver"
        }
    }

    private func hookPendingText(for target: HookTargetID) -> String {
        switch target {
        case .claude:
            return "Connecting Claude Code..."
        case .codex:
            return "Connecting Codex..."
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

        if source == "Codex", let parentSessionID = codexSubagentParents[sessionID] {
            attachCodexSubagentEvent(
                envelope.event,
                subagentSessionID: sessionID,
                parentSessionID: parentSessionID,
                receivedAt: envelope.receivedAt
            )
            refreshActiveSessions(now: envelope.receivedAt)
            ensureActivityRefreshTimer()
            return
        }

        let isExistingSession = sessionsBySource[source]?[sessionID] != nil
            || transcriptSessionsBySource[source]?[sessionID] != nil
        if source == "Codex", !isExistingSession, !shouldStartCodexSession(from: envelope.event) {
            refreshActiveSessions(now: envelope.receivedAt)
            return
        }

        var sourceSessions = sessionsBySource[source] ?? [:]
        var tracked = sourceSessions[sessionID] ?? TrackedSession(
            event: envelope.event,
            updatedAt: envelope.receivedAt,
            taskTitle: nil,
            latestUserLine: nil
        )

        tracked.event = envelope.event
        tracked.updatedAt = envelope.receivedAt
        if let terminalWindowContext = terminalJumpService.currentTerminalWindowContext(
            sessionID: sessionID,
            workingDirectory: envelope.event.workingDirectory
        ) {
            tracked.terminalWindowContext = terminalWindowContext
        }
        if let latestUserLine = cleanedMessage(envelope.event.message, prefix: "Prompt:"), !latestUserLine.isEmpty {
            tracked.latestUserLine = latestUserLine
        }

        updateSubagents(for: envelope.event, receivedAt: envelope.receivedAt, tracked: &tracked)
        sourceSessions[sessionID] = tracked
        sessionsBySource[source] = sourceSessions
        refreshActiveSessions(now: envelope.receivedAt)
        ensureActivityRefreshTimer()
    }

    private func attachCodexSubagentEvent(
        _ event: AgentEvent,
        subagentSessionID: String,
        parentSessionID: String,
        receivedAt: Date
    ) {
        var sourceSessions = sessionsBySource["Codex"] ?? [:]
        var parent = sourceSessions[parentSessionID]
            ?? transcriptSessionsBySource["Codex"]?[parentSessionID]
            ?? parentPlaceholderSession(for: event, parentSessionID: parentSessionID, receivedAt: receivedAt)

        if event.kind == .completed {
            parent.subagents.removeValue(forKey: subagentSessionID)
        } else {
            let prompt = cleanedMessage(event.message, prefix: "Prompt:")
            var subagent = parent.subagents[subagentSessionID] ?? TrackedSubagent(
                id: subagentSessionID,
                name: event.subagentName ?? "Subagent",
                taskTitle: prompt ?? event.subagentTask ?? "Working",
                actionText: humanizedSummary(for: event),
                latestKind: event.kind,
                startedAt: receivedAt,
                updatedAt: receivedAt
            )

            if let prompt, !prompt.isEmpty, subagent.taskTitle == "Working" {
                subagent.taskTitle = prompt
            }
            if let subagentName = event.subagentName, !subagentName.isEmpty {
                subagent.name = subagentName
            }
            subagent.actionText = humanizedSummary(for: event)
            subagent.latestKind = event.kind == .completed ? .thinking : event.kind
            subagent.updatedAt = receivedAt
            parent.subagents[subagentSessionID] = subagent
        }

        parent.updatedAt = max(parent.updatedAt, receivedAt)
        sourceSessions[parentSessionID] = parent
        sourceSessions.removeValue(forKey: subagentSessionID)
        sessionsBySource["Codex"] = sourceSessions
        transcriptSessionsBySource["Codex"]?.removeValue(forKey: subagentSessionID)
    }

    private func shouldStartCodexSession(from event: AgentEvent) -> Bool {
        switch event.kind {
        case .thinking, .reading, .runningCommand, .editingCode, .permissionRequest, .error:
            return true
        case .completed, .idle, .unknown:
            return false
        }
    }

    private func hasActiveSubagents(source: String, sessionID: String?) -> Bool {
        guard let sessionID, !sessionID.isEmpty else {
            return false
        }
        return !(sessionsBySource[source]?[sessionID]?.subagents.isEmpty ?? true)
    }

    private func updateSubagents(for event: AgentEvent, receivedAt: Date, tracked: inout TrackedSession) {
        if event.toolName == "Agent" {
            tracked.pendingSubagent = PendingSubagent(
                name: event.subagentName ?? "Subagent",
                taskTitle: event.subagentTask ?? cleanedSubagentTask(from: event.message) ?? "Working",
                createdAt: receivedAt
            )
            return
        }

        switch event.hookEventName {
        case "SubagentStart", "TaskCreated":
            let pending = tracked.pendingSubagent
            let id = "\(receivedAt.timeIntervalSinceReferenceDate)-\(pending?.name ?? event.subagentName ?? "Subagent")"
            tracked.subagents[id] = TrackedSubagent(
                id: id,
                name: event.subagentName ?? pending?.name ?? "Subagent",
                taskTitle: event.subagentTask ?? pending?.taskTitle ?? "Working",
                actionText: "Starting",
                latestKind: .thinking,
                startedAt: receivedAt,
                updatedAt: receivedAt
            )
            tracked.pendingSubagent = nil
        case "SubagentStop", "TaskCompleted":
            if let id = mostRecentSubagentID(in: tracked) {
                tracked.subagents.removeValue(forKey: id)
            }
        case "SessionEnd":
            tracked.pendingSubagent = nil
            tracked.subagents.removeAll()
        default:
            guard shouldAttachEventToSubagent(event),
                  let id = mostRecentSubagentID(in: tracked),
                  var subagent = tracked.subagents[id] else {
                return
            }
            subagent.actionText = humanizedSummary(for: event)
            subagent.latestKind = event.kind
            subagent.updatedAt = receivedAt
            tracked.subagents[id] = subagent
        }
    }

    private func shouldAttachEventToSubagent(_ event: AgentEvent) -> Bool {
        switch event.hookEventName {
        case "PreToolUse", "PostToolUseFailure", "PermissionRequest", "PermissionDenied":
            return event.toolName != "Agent"
        default:
            return false
        }
    }

    private func mostRecentSubagentID(in tracked: TrackedSession) -> String? {
        tracked.subagents.values
            .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
            .first?
            .id
    }

    private func refreshActiveSessions(now: Date = Date()) {
        pruneExpiredSessions(now: now)

        let aliveSessions = visibleSessions(from: mergedSessions())
        let activeSessions = filteredActiveSessions(from: aliveSessions, now: now)

        sourceSections = buildSourceSections(from: aliveSessions, activeSessions: activeSessions, now: now)
        focusedSession = selectFocusedSession(
            activeSections: buildSourceSections(from: activeSessions, activeSessions: activeSessions, now: now),
            aliveSections: sourceSections,
            now: now
        )

        updateActivityPresentation(activeSections: buildSourceSections(from: activeSessions, activeSessions: activeSessions, now: now), now: now)

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

        if var codexSessions = merged["Codex"] {
            for subagentSessionID in codexSubagentParents.keys {
                codexSessions.removeValue(forKey: subagentSessionID)
            }
            merged["Codex"] = codexSessions
        }

        return merged
    }

    private func visibleSessions(
        from sessions: [String: [String: TrackedSession]]
    ) -> [String: [String: TrackedSession]] {
        var visible: [String: [String: TrackedSession]] = [:]

        for (source, sourceSessions) in sessions {
            var visibleSourceSessions: [String: TrackedSession] = [:]

            for (sessionID, tracked) in sourceSessions {
                if source == "Codex", codexSubagentParents[sessionID] != nil {
                    continue
                }
                if source == "Codex", shouldHideCodexTopLevelSession(tracked) {
                    continue
                }

                let key = sessionKey(source: source, sessionID: sessionID)
                if let archivedAt = archivedSessions[key] {
                    guard tracked.updatedAt > archivedAt else {
                        continue
                    }
                    archivedSessions.removeValue(forKey: key)
                }
                visibleSourceSessions[sessionID] = tracked
            }

            if !visibleSourceSessions.isEmpty {
                visible[source] = visibleSourceSessions
            }
        }

        return visible
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
            var filtered: [String: TrackedSession] = [:]
            for (sessionID, tracked) in sourceSessions {
                if source == "Codex", codexSubagentParents[sessionID] != nil {
                    continue
                }

                var nextTracked = tracked
                nextTracked.subagents = tracked.subagents.filter { _, subagent in
                    now.timeIntervalSince(subagent.updatedAt) < lifetime(forSubagent: subagent)
                }
                if source == "Codex", shouldHideCodexTopLevelSession(nextTracked) {
                    continue
                }
                if !nextTracked.subagents.isEmpty {
                    filtered[sessionID] = nextTracked
                    continue
                }
                guard now.timeIntervalSince(nextTracked.updatedAt) < aliveSessionLifetime(for: nextTracked.event, source: source) else {
                    continue
                }
                filtered[sessionID] = nextTracked
            }
            if filtered.isEmpty {
                pruned.removeValue(forKey: source)
            } else {
                pruned[source] = filtered
            }
        }
        return pruned
    }

    private func filteredActiveSessions(
        from sessions: [String: [String: TrackedSession]],
        now: Date
    ) -> [String: [String: TrackedSession]] {
        var filtered: [String: [String: TrackedSession]] = [:]

        for (source, sourceSessions) in sessions {
            let activeSourceSessions = sourceSessions.filter { _, tracked in
                if !tracked.subagents.isEmpty {
                    return true
                }
                return now.timeIntervalSince(tracked.updatedAt) < activeSessionLifetime(for: tracked.event, source: source)
            }
            if !activeSourceSessions.isEmpty {
                filtered[source] = activeSourceSessions
            }
        }

        return filtered
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
        var nextCodexSessions = transcriptSessionsBySource["Codex"] ?? [:]
        let now = Date()

        for snapshot in snapshots where !snapshot.isSubagent {
            for subagent in snapshot.subagents {
                codexSubagentParents[subagent.sessionID] = snapshot.sessionID
                nextCodexSessions.removeValue(forKey: subagent.sessionID)
                sessionsBySource["Codex"]?.removeValue(forKey: subagent.sessionID)
            }

            let isAlreadyTracked = nextCodexSessions[snapshot.sessionID] != nil
                || sessionsBySource["Codex"]?[snapshot.sessionID] != nil
            guard !snapshot.subagents.isEmpty || shouldAcceptCodexSnapshot(snapshot, isAlreadyTracked: isAlreadyTracked, now: now) else {
                continue
            }

            var tracked = nextCodexSessions[snapshot.sessionID] ?? sessionsBySource["Codex"]?[snapshot.sessionID] ?? TrackedSession(
                event: snapshot.event,
                updatedAt: snapshot.updatedAt,
                taskTitle: snapshot.taskTitle,
                latestUserLine: snapshot.latestUserLine
            )
            tracked.event = snapshot.event
            tracked.updatedAt = snapshot.updatedAt
            tracked.taskTitle = snapshot.taskTitle ?? tracked.taskTitle
            tracked.latestUserLine = snapshot.latestUserLine ?? tracked.latestUserLine
            for subagent in snapshot.subagents {
                tracked.subagents[subagent.sessionID] = trackedSubagent(from: subagent)
                tracked.updatedAt = max(tracked.updatedAt, subagent.updatedAt)
            }
            nextCodexSessions[snapshot.sessionID] = tracked
        }

        for snapshot in snapshots where snapshot.isSubagent {
            guard let parentSessionID = snapshot.parentSessionID else {
                continue
            }
            codexSubagentParents[snapshot.sessionID] = parentSessionID
            nextCodexSessions.removeValue(forKey: snapshot.sessionID)
            sessionsBySource["Codex"]?.removeValue(forKey: snapshot.sessionID)

            guard now.timeIntervalSince(snapshot.updatedAt) < subagentLifetime else {
                nextCodexSessions[parentSessionID]?.subagents.removeValue(forKey: snapshot.sessionID)
                continue
            }

            if nextCodexSessions[parentSessionID] == nil {
                if let hookTracked = sessionsBySource["Codex"]?[parentSessionID] {
                    nextCodexSessions[parentSessionID] = hookTracked
                } else {
                    nextCodexSessions[parentSessionID] = parentPlaceholderSession(for: snapshot, parentSessionID: parentSessionID)
                }
            }

            nextCodexSessions[parentSessionID]?.subagents[snapshot.sessionID] = trackedSubagent(from: snapshot)
        }

        if nextCodexSessions.isEmpty {
            transcriptSessionsBySource.removeValue(forKey: "Codex")
        } else {
            transcriptSessionsBySource["Codex"] = nextCodexSessions
        }

        refreshActiveSessions()
    }

    private func shouldAcceptCodexSnapshot(_ snapshot: CodexTranscriptSnapshot, isAlreadyTracked: Bool, now: Date) -> Bool {
        if shouldRemoveSession(for: snapshot.event, source: "Codex", now: now, updatedAt: snapshot.updatedAt) {
            return false
        }

        if isAlreadyTracked {
            return true
        }

        switch snapshot.event.kind {
        case .completed, .idle, .unknown:
            return false
        case .thinking, .reading, .runningCommand, .editingCode, .permissionRequest, .error:
            return now.timeIntervalSince(snapshot.updatedAt) < activeSessionLifetime(for: snapshot.event, source: "Codex")
        }
    }

    private func parentPlaceholderSession(for snapshot: CodexTranscriptSnapshot, parentSessionID: String) -> TrackedSession {
        let event = AgentEvent(
            kind: .thinking,
            hookEventName: "TranscriptSubagentParent",
            message: "Watching subagents",
            sessionID: parentSessionID,
            workingDirectory: snapshot.event.workingDirectory
        )
        return TrackedSession(
            event: event,
            updatedAt: snapshot.updatedAt,
            taskTitle: nil,
            latestUserLine: nil
        )
    }

    private func parentPlaceholderSession(
        for event: AgentEvent,
        parentSessionID: String,
        receivedAt: Date
    ) -> TrackedSession {
        let parentEvent = AgentEvent(
            kind: .thinking,
            hookEventName: "CodexSubagentParent",
            message: "Watching subagents",
            sessionID: parentSessionID,
            workingDirectory: event.workingDirectory
        )
        return TrackedSession(
            event: parentEvent,
            updatedAt: receivedAt,
            taskTitle: nil,
            latestUserLine: nil
        )
    }

    private func trackedSubagent(from snapshot: CodexTranscriptSnapshot) -> TrackedSubagent {
        TrackedSubagent(
            id: snapshot.sessionID,
            name: snapshot.subagentName ?? snapshot.subagentRole ?? "Subagent",
            taskTitle: snapshot.taskTitle ?? snapshot.latestUserLine ?? "Working",
            actionText: humanizedSummary(for: snapshot.event),
            latestKind: snapshot.event.kind == .completed ? .thinking : snapshot.event.kind,
            startedAt: snapshot.startedAt ?? snapshot.updatedAt,
            updatedAt: snapshot.updatedAt
        )
    }

    private func trackedSubagent(from snapshot: CodexSubagentSnapshot) -> TrackedSubagent {
        TrackedSubagent(
            id: snapshot.sessionID,
            name: snapshot.name,
            taskTitle: snapshot.taskTitle,
            actionText: snapshot.latestSummary ?? (snapshot.kind == .completed ? "Ready" : "Working"),
            latestKind: snapshot.kind,
            startedAt: snapshot.startedAt,
            updatedAt: snapshot.updatedAt
        )
    }

    private func sessionKey(source: String, sessionID: String) -> String {
        "\(source)-\(sessionID)"
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

    private func buildSourceSections(
        from sessions: [String: [String: TrackedSession]],
        activeSessions: [String: [String: TrackedSession]],
        now: Date
    ) -> [SourceSection] {
        ["Claude", "Codex"].compactMap { source in
            guard let sourceSessions = sessions[source], !sourceSessions.isEmpty else {
                return nil
            }

            let displays = sourceSessions.map { sessionID, tracked in
                sessionDisplay(
                    source: source,
                    sessionID: sessionID,
                    tracked: tracked,
                    isActive: activeSessions[source]?[sessionID] != nil,
                    now: now
                )
            }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && !rhs.isActive
                }
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.updatedAt > rhs.updatedAt
            }

            return SourceSection(
                source: source,
                count: displays.count,
                headline: sectionHeadline(for: displays),
                sessions: displays
            )
        }
    }

    private func shouldHideCodexTopLevelSession(_ tracked: TrackedSession) -> Bool {
        guard tracked.subagents.isEmpty else {
            return false
        }

        switch tracked.event.kind {
        case .completed:
            return false
        case .idle, .unknown:
            return true
        case .thinking:
            let line = tracked.latestUserLine ?? cleanedMessage(tracked.event.message, prefix: "Prompt:")
            if let line, line.hasPrefix("You are a helpful assist") || line.hasPrefix("You are Codex") {
                return true
            }
            return false
        case .reading, .runningCommand, .editingCode, .permissionRequest, .error:
            return false
        }
    }

    private func sectionHeadline(for displays: [SessionDisplay]) -> String {
        guard let first = displays.first else {
            return "Watching"
        }
        if !first.subagents.isEmpty {
            return first.subagents.count == 1 ? "1 subagent" : "\(first.subagents.count) subagents"
        }
        return first.taskTitle ?? first.eventText
    }

    private func sessionDisplay(
        source: String,
        sessionID: String,
        tracked: TrackedSession,
        isActive: Bool,
        now: Date
    ) -> SessionDisplay {
        let subagents = subagentDisplays(from: tracked.subagents, now: now)
        let effectiveKind = effectiveKind(for: tracked)
        let effectiveEventText = eventText(for: tracked.event, isActive: isActive, subagentCount: subagents.count)
        let effectiveBubbleText = bubbleSummary(for: source, event: tracked.event, subagents: subagents)

        return SessionDisplay(
            source: source,
            sessionID: sessionID,
            taskTitle: sessionTitle(for: tracked, subagents: subagents),
            latestUserLine: tracked.latestUserLine,
            subagents: subagents,
            workspaceName: workspaceName(for: tracked.event.workingDirectory),
            eventText: effectiveEventText,
            bubbleText: effectiveBubbleText,
            workingDirectory: tracked.event.workingDirectory,
            workingDirectoryText: workingDirectoryText(for: tracked.event.workingDirectory),
            terminalWindowContext: tracked.terminalWindowContext,
            shortSessionID: shortenedSessionID(sessionID),
            updatedAt: tracked.updatedAt,
            priority: subagents.isEmpty ? eventPriority(for: tracked.event.kind) : 6,
            kind: effectiveKind,
            isActive: isActive
        )
    }

    private func sessionTitle(for tracked: TrackedSession, subagents: [SubagentDisplay]) -> String? {
        if subagents.count > 1 {
            return "\(subagents.count) subagents"
        }
        if let subagent = subagents.first {
            return subagent.taskTitle
        }
        return tracked.taskTitle
    }

    private func effectiveKind(for tracked: TrackedSession) -> AgentEventKind {
        guard let subagent = tracked.subagents.values.sorted(by: { $0.updatedAt > $1.updatedAt }).first else {
            return tracked.event.kind
        }
        return subagent.latestKind == .completed ? .thinking : subagent.latestKind
    }

    private func subagentDisplays(from subagents: [String: TrackedSubagent], now: Date) -> [SubagentDisplay] {
        subagents.values
            .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
            .map { subagent in
                SubagentDisplay(
                    id: subagent.id,
                    name: subagent.name,
                    taskTitle: subagent.taskTitle,
                    actionText: subagent.actionText,
                    durationText: elapsedText(from: subagent.startedAt, to: now)
                )
            }
    }

    private func lifetime(forSubagent subagent: TrackedSubagent) -> TimeInterval {
        subagent.latestKind == .completed ? completedSubagentLifetime : subagentLifetime
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

    private func eventText(for event: AgentEvent, isActive: Bool, subagentCount: Int) -> String {
        if subagentCount > 0 {
            return subagentCount == 1 ? "1 subagent" : "\(subagentCount) subagents"
        }
        if !isActive {
            if event.kind == .completed {
                return "Waiting"
            }
            return "Idle"
        }
        return humanizedSummary(for: event)
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

    private func selectFocusedSession(
        activeSections: [SourceSection],
        aliveSections: [SourceSection],
        now: Date
    ) -> SessionDisplay? {
        let activeCandidates = sortedFocusCandidates(from: activeSections)
        let aliveCandidates = sortedFocusCandidates(from: aliveSections)
        let candidates = activeCandidates.isEmpty ? aliveCandidates : activeCandidates

        guard let bestCandidate = candidates.first else {
            focusedSessionID = nil
            return nil
        }

        guard let focusedSessionID else {
            self.focusedSessionID = bestCandidate.id
            focusedSessionChangedAt = now
            return bestCandidate
        }

        guard let currentFocused = candidates.first(where: { $0.id == focusedSessionID }) else {
            self.focusedSessionID = bestCandidate.id
            focusedSessionChangedAt = now
            return bestCandidate
        }

        if currentFocused.id == bestCandidate.id {
            return currentFocused
        }

        if bestCandidate.priority > currentFocused.priority {
            self.focusedSessionID = bestCandidate.id
            focusedSessionChangedAt = now
            return bestCandidate
        }

        if now.timeIntervalSince(focusedSessionChangedAt) < focusHoldDuration {
            return currentFocused
        }

        self.focusedSessionID = bestCandidate.id
        focusedSessionChangedAt = now
        return bestCandidate
    }

    private func sortedFocusCandidates(from sections: [SourceSection]) -> [SessionDisplay] {
        sections
            .flatMap(\.sessions)
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && !rhs.isActive
                }
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private func updateActivityPresentation(activeSections: [SourceSection], now: Date) {
        guard !activeSections.isEmpty else {
            mood = .classic
            bubbleText = "Idle"
            return
        }

        if let focusedSession, focusedSession.isActive {
            mood = moodForFocusedSession(focusedSession)
        } else if let fallbackSession = activeSections.flatMap(\.sessions).first {
            mood = moodForFocusedSession(fallbackSession)
        }

        let summaries = activeSections.compactMap { section in
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

    private func bubbleSummary(for source: String, event: AgentEvent, subagents: [SubagentDisplay]) -> String {
        if let subagent = subagents.first {
            return "\(source): \(subagent.name) \(subagent.actionText)"
        }
        return "\(source): \(humanizedSummary(for: event))"
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
            return age > 3
        case .reading, .runningCommand, .editingCode, .thinking:
            return false
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
                return summarizedCommand(command)
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

    private func cleanedSubagentTask(from message: String?) -> String? {
        guard let message = cleanedMessage(message, prefix: "Subagent:") else {
            return nil
        }
        guard let open = message.firstIndex(of: "("),
              let close = message.lastIndex(of: ")"),
              open < close else {
            return nil
        }
        return String(message[message.index(after: open)..<close])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func elapsedText(from startDate: Date, to endDate: Date) -> String {
        let seconds = max(0, Int(endDate.timeIntervalSince(startDate)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes < 60 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
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

    private func summarizedCommand(_ command: String) -> String {
        let normalized = normalizedDisplayCommand(command)
        let tokens = shellTokens(in: normalized)
        guard let first = tokens.first?.lowercased() else {
            return "Running"
        }

        switch first {
        case "open":
            if let target = commandDisplayTarget(from: tokens.dropFirst()) {
                return "Open \(target)"
            }
            return "Open"
        case "git":
            if let subcommand = tokens.dropFirst().first?.lowercased() {
                switch subcommand {
                case "commit":
                    return "Git commit"
                case "push":
                    return "Git push"
                case "pull":
                    return "Git pull"
                case "add":
                    return "Git add"
                case "checkout", "switch":
                    return "Git switch"
                case "merge":
                    return "Git merge"
                case "rebase":
                    return "Git rebase"
                default:
                    return "Git \(subcommand)"
                }
            }
            return "Git"
        case "swift":
            if let subcommand = tokens.dropFirst().first?.lowercased() {
                return "Swift \(subcommand)"
            }
            return "Swift"
        case "python", "python3", "uv", "node", "npm", "pnpm", "yarn", "tmux":
            if let target = commandDisplayTarget(from: tokens.dropFirst()) {
                return "\(first.capitalized) \(target)"
            }
            return first.capitalized
        default:
            return "Bash \(clipped(normalized, limit: 24))"
        }
    }

    private func normalizedDisplayCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstSegment = trimmed
            .components(separatedBy: "&&")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed

        let tokens = shellTokens(in: firstSegment)
        guard let first = tokens.first?.lowercased() else {
            return firstSegment
        }

        let shellWrappers = ["bash", "zsh", "sh"]
        if shellWrappers.contains(first), tokens.count >= 3, tokens[1] == "-lc" {
            let wrapped = tokens.dropFirst(2).joined(separator: " ")
            let unquoted = wrapped.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return normalizedDisplayCommand(unquoted)
        }

        var startIndex = 0
        while startIndex < tokens.count {
            let token = tokens[startIndex]
            if token == "env" {
                startIndex += 1
                continue
            }
            if token.contains("="), !token.hasPrefix("/"), !token.hasPrefix("./") {
                startIndex += 1
                continue
            }
            break
        }

        return tokens.dropFirst(startIndex).joined(separator: " ")
    }

    private func shellTokens(in command: String) -> [String] {
        command
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private func commandDisplayTarget<S: Sequence>(from tokens: S) -> String? where S.Element == String {
        for token in tokens {
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !cleaned.isEmpty, !cleaned.hasPrefix("-") else { continue }
            if cleaned.hasSuffix(".app") || cleaned.contains("/") || cleaned.hasPrefix("~") || cleaned.hasPrefix(".") {
                let component = URL(fileURLWithPath: cleaned.replacingOccurrences(of: "file://", with: "")).lastPathComponent
                return clipped(component.isEmpty ? cleaned : component, limit: 20)
            }
            if cleaned.rangeOfCharacter(from: .letters) != nil {
                return clipped(cleaned, limit: 20)
            }
        }
        return nil
    }

    private func activeSessionLifetime(for event: AgentEvent, source: String) -> TimeInterval {
        switch event.kind {
        case .completed:
            return 4
        case .permissionRequest, .error:
            return 15
        case .idle, .thinking, .reading, .runningCommand, .editingCode, .unknown:
            return 30
        }
    }

    private func aliveSessionLifetime(for event: AgentEvent, source: String) -> TimeInterval {
        if isSessionExitEvent(event, source: source) {
            return 4
        }

        switch source {
        case "Claude":
            return .infinity
        case "Codex":
            switch event.kind {
            case .completed:
                return 120
            case .idle, .unknown:
                return 30
            case .thinking, .reading, .runningCommand, .editingCode, .permissionRequest, .error:
                return .infinity
            }
        default:
            return activeSessionLifetime(for: event, source: source)
        }
    }

    private func shouldRemoveSession(
        for event: AgentEvent,
        source: String,
        now: Date,
        updatedAt: Date
    ) -> Bool {
        now.timeIntervalSince(updatedAt) >= aliveSessionLifetime(for: event, source: source)
    }

    private func isSessionExitEvent(_ event: AgentEvent, source: String) -> Bool {
        source == "Claude" && event.hookEventName == "SessionEnd"
    }
}

extension Notification.Name {
    static let clawdPalDragEnded = Notification.Name("clawdPalDragEnded")
    static let clawdPalResetWindowPosition = Notification.Name("clawdPalResetWindowPosition")
    static let clawdPalSetPanelOpen = Notification.Name("clawdPalSetPanelOpen")
}
