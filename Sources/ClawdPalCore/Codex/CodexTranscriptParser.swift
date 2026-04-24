import Foundation

public struct CodexTranscriptSnapshot: Equatable, Sendable {
    public var sessionID: String
    public var parentSessionID: String?
    public var subagentName: String?
    public var subagentRole: String?
    public var subagents: [CodexSubagentSnapshot]
    public var taskTitle: String?
    public var latestUserLine: String?
    public var event: AgentEvent
    public var startedAt: Date?
    public var updatedAt: Date

    public init(
        sessionID: String,
        parentSessionID: String? = nil,
        subagentName: String? = nil,
        subagentRole: String? = nil,
        subagents: [CodexSubagentSnapshot] = [],
        taskTitle: String? = nil,
        latestUserLine: String? = nil,
        event: AgentEvent,
        startedAt: Date? = nil,
        updatedAt: Date
    ) {
        self.sessionID = sessionID
        self.parentSessionID = parentSessionID
        self.subagentName = subagentName
        self.subagentRole = subagentRole
        self.subagents = subagents
        self.taskTitle = taskTitle
        self.latestUserLine = latestUserLine
        self.event = event
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public var isSubagent: Bool {
        parentSessionID != nil
    }
}

public struct CodexSubagentSnapshot: Equatable, Sendable {
    public var sessionID: String
    public var parentSessionID: String
    public var name: String
    public var role: String?
    public var taskTitle: String
    public var latestSummary: String?
    public var kind: AgentEventKind
    public var startedAt: Date
    public var updatedAt: Date

    public init(
        sessionID: String,
        parentSessionID: String,
        name: String,
        role: String? = nil,
        taskTitle: String,
        latestSummary: String? = nil,
        kind: AgentEventKind,
        startedAt: Date,
        updatedAt: Date
    ) {
        self.sessionID = sessionID
        self.parentSessionID = parentSessionID
        self.name = name
        self.role = role
        self.taskTitle = taskTitle
        self.latestSummary = latestSummary
        self.kind = kind
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

public enum CodexTranscriptParser {
    public struct Accumulator {
        private var sessionID: String?
        private var parentSessionID: String?
        private var subagentName: String?
        private var subagentRole: String?
        private var spawnedSubagents: [String: CodexSubagentSnapshot] = [:]
        private var workingDirectory: String?
        private var taskTitle: String?
        private var currentTurn: TurnState?
        private var lastCompletedTurn: CompletedTurn?
        private var sessionStartedAt: Date?
        private var latestTimestamp: Date?
        private var activityCutoff: Date?

        public init(fallbackTitle: String? = nil, activityCutoff: Date? = nil) {
            self.taskTitle = CodexTranscriptParser.cleanedInlineText(fallbackTitle)
            self.activityCutoff = activityCutoff
        }

        public mutating func consume(text: String) throws {
            for rawLine in text.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                try consume(line: String(line))
            }
        }

        public mutating func consume(line: String) throws {
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
            guard let object = value.objectValue else { return }

            let timestamp = CodexTranscriptParser.dateValue(in: object, key: "timestamp")
            let lineType = object["type"]?.stringValue

            if lineType != "session_meta",
               let activityCutoff,
               let timestamp,
               timestamp < activityCutoff {
                return
            }

            latestTimestamp = CodexTranscriptParser.maxDate(latestTimestamp, timestamp)

            switch lineType {
            case "session_meta":
                guard let payload = object["payload"]?.objectValue else { return }
                sessionID = CodexTranscriptParser.stringValue(in: payload, keys: ["id"]) ?? sessionID
                workingDirectory = CodexTranscriptParser.stringValue(in: payload, keys: ["cwd"]) ?? workingDirectory
                sessionStartedAt = CodexTranscriptParser.dateValue(in: payload, key: "timestamp") ?? timestamp ?? sessionStartedAt
                let threadSpawn = CodexTranscriptParser.subagentThreadSpawn(in: payload)
                subagentName = CodexTranscriptParser.stringValue(in: payload, keys: ["agent_nickname"])
                    ?? threadSpawn.flatMap { CodexTranscriptParser.stringValue(in: $0, keys: ["agent_nickname"]) }
                    ?? subagentName
                subagentRole = CodexTranscriptParser.stringValue(in: payload, keys: ["agent_role"])
                    ?? threadSpawn.flatMap { CodexTranscriptParser.stringValue(in: $0, keys: ["agent_role"]) }
                    ?? subagentRole
                parentSessionID = threadSpawn.flatMap { CodexTranscriptParser.stringValue(in: $0, keys: ["parent_thread_id", "parentThreadID", "parent_id"]) } ?? parentSessionID
            case "event_msg":
                guard let payload = object["payload"]?.objectValue else { return }
                switch payload["type"]?.stringValue {
                case "collab_agent_spawn_end":
                    recordSubagentSpawn(from: payload, timestamp: timestamp)
                case "task_started":
                    let turnID = CodexTranscriptParser.stringValue(in: payload, keys: ["turn_id"]) ?? UUID().uuidString
                    currentTurn = TurnState(
                        turnID: turnID,
                        taskTitle: taskTitle,
                        latestUserLine: nil,
                        latestUserAt: nil,
                        latestAction: nil,
                        latestActionAt: nil,
                        startedAt: timestamp
                    )
                case "user_message":
                    if let cleanedUserLine = CodexTranscriptParser.cleanedUserLine(from: CodexTranscriptParser.stringValue(in: payload, keys: ["message"])),
                       var activeTurn = currentTurn {
                        activeTurn.latestUserLine = cleanedUserLine
                        activeTurn.latestUserAt = timestamp ?? activeTurn.latestUserAt
                        currentTurn = activeTurn
                    }
                case "thread_name_updated":
                    taskTitle = CodexTranscriptParser.cleanedInlineText(CodexTranscriptParser.stringValue(in: payload, keys: ["thread_name"]))
                    if var activeTurn = currentTurn {
                        activeTurn.taskTitle = taskTitle
                        currentTurn = activeTurn
                    }
                case "task_complete":
                    let completedTurnID = CodexTranscriptParser.stringValue(in: payload, keys: ["turn_id"])
                    if let activeTurn = currentTurn, completedTurnID == nil || completedTurnID == activeTurn.turnID {
                        lastCompletedTurn = CompletedTurn(
                            taskTitle: activeTurn.taskTitle ?? taskTitle,
                            latestUserLine: activeTurn.latestUserLine,
                            completedAt: timestamp ?? latestTimestamp ?? Date.distantPast
                        )
                        currentTurn = nil
                    }
                default:
                    break
                }
            case "response_item":
                guard let payload = object["payload"]?.objectValue else { return }
                switch payload["type"]?.stringValue {
                case "message":
                    recordSubagentNotification(from: payload, timestamp: timestamp)
                case "function_call", "custom_tool_call":
                    if var activeTurn = currentTurn,
                       let event = CodexTranscriptParser.event(from: payload, sessionID: sessionID, workingDirectory: workingDirectory) {
                        activeTurn.latestAction = event
                        activeTurn.latestActionAt = timestamp ?? activeTurn.latestActionAt
                        currentTurn = activeTurn
                    }
                default:
                    break
                }
            default:
                break
            }
        }

        public func snapshot() -> CodexTranscriptSnapshot? {
            guard let sessionID else {
                return nil
            }

            let resolvedTitle = taskTitle ?? CodexTranscriptParser.clipped(currentTurn?.latestUserLine ?? lastCompletedTurn?.latestUserLine, limit: 40)
            let resolvedEvent: AgentEvent
            let updatedAt: Date
            let resolvedUserLine: String?

            if let currentTurn, let latestAction = currentTurn.latestAction, let latestActionAt = currentTurn.latestActionAt {
                resolvedEvent = latestAction
                updatedAt = latestActionAt
                resolvedUserLine = currentTurn.latestUserLine
            } else if let currentTurn, let latestUserLine = currentTurn.latestUserLine, let latestUserAt = currentTurn.latestUserAt {
                resolvedEvent = AgentEvent(
                    kind: .thinking,
                    hookEventName: "UserPromptSubmit",
                    message: "Prompt: \(CodexTranscriptParser.clipped(latestUserLine, limit: 72) ?? latestUserLine)",
                    sessionID: sessionID,
                    workingDirectory: workingDirectory
                )
                updatedAt = latestUserAt
                resolvedUserLine = latestUserLine
            } else if let lastCompletedTurn {
                resolvedEvent = AgentEvent(
                    kind: .completed,
                    hookEventName: "Stop",
                    message: "Done.",
                    sessionID: sessionID,
                    workingDirectory: workingDirectory
                )
                updatedAt = lastCompletedTurn.completedAt
                resolvedUserLine = lastCompletedTurn.latestUserLine
            } else {
                resolvedEvent = AgentEvent(
                    kind: .idle,
                    hookEventName: "SessionStart",
                    message: "Session started",
                    sessionID: sessionID,
                    workingDirectory: workingDirectory
                )
                updatedAt = latestTimestamp ?? Date.distantPast
                resolvedUserLine = nil
            }

            return CodexTranscriptSnapshot(
                sessionID: sessionID,
                parentSessionID: parentSessionID,
                subagentName: subagentName,
                subagentRole: subagentRole,
                subagents: spawnedSubagents.values.sorted { lhs, rhs in
                    if lhs.kind != rhs.kind {
                        return lhs.kind != .completed && rhs.kind == .completed
                    }
                    return lhs.updatedAt > rhs.updatedAt
                },
                taskTitle: resolvedTitle,
                latestUserLine: resolvedUserLine,
                event: resolvedEvent,
                startedAt: sessionStartedAt,
                updatedAt: updatedAt
            )
        }

        private mutating func recordSubagentSpawn(from payload: [String: JSONValue], timestamp: Date?) {
            guard let parentID = CodexTranscriptParser.stringValue(in: payload, keys: ["sender_thread_id", "parent_thread_id"]),
                  let childID = CodexTranscriptParser.stringValue(in: payload, keys: ["new_thread_id"]) else {
                return
            }

            let startedAt = timestamp ?? Date.distantPast
            let name = CodexTranscriptParser.stringValue(in: payload, keys: ["new_agent_nickname"])
                ?? CodexTranscriptParser.stringValue(in: payload, keys: ["new_agent_role"])
                ?? "Subagent"
            let prompt = CodexTranscriptParser.cleanedInlineText(
                CodexTranscriptParser.stringValue(in: payload, keys: ["prompt"])
            ) ?? "Working"

            spawnedSubagents[childID] = CodexSubagentSnapshot(
                sessionID: childID,
                parentSessionID: parentID,
                name: name,
                role: CodexTranscriptParser.stringValue(in: payload, keys: ["new_agent_role"]),
                taskTitle: prompt,
                latestSummary: nil,
                kind: .thinking,
                startedAt: startedAt,
                updatedAt: startedAt
            )
        }

        private mutating func recordSubagentNotification(from payload: [String: JSONValue], timestamp: Date?) {
            guard let text = CodexTranscriptParser.messageText(from: payload),
                  let notification = CodexTranscriptParser.subagentNotification(from: text),
                  var subagent = spawnedSubagents[notification.sessionID] else {
                return
            }

            subagent.latestSummary = notification.summary
            subagent.kind = .completed
            subagent.updatedAt = timestamp ?? subagent.updatedAt
            spawnedSubagents[notification.sessionID] = subagent
        }
    }

    private struct TurnState {
        var turnID: String
        var taskTitle: String?
        var latestUserLine: String?
        var latestUserAt: Date?
        var latestAction: AgentEvent?
        var latestActionAt: Date?
        var startedAt: Date?
    }

    private struct CompletedTurn {
        var taskTitle: String?
        var latestUserLine: String?
        var completedAt: Date
    }

    private struct SubagentNotification {
        var sessionID: String
        var summary: String
    }

    private static let readOnlyCommands: Set<String> = [
        "cat", "sed", "head", "tail", "nl", "less", "more"
    ]

    private static let searchCommands: Set<String> = [
        "rg", "grep", "find"
    ]

    private static let ignoredCommandPrefixes: [String] = [
        "git status",
        "git diff",
        "git branch",
        "git remote",
        "swift build",
        "swift test",
        "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test",
        "./scripts/build-app.sh"
    ]

    private static let editTools: Set<String> = [
        "apply_patch"
    ]

    private static let runTools: Set<String> = [
        "exec_command", "write_stdin"
    ]

    private static let readTools: Set<String> = [
        "open", "find", "search_query", "read_mcp_resource", "list_mcp_resources", "list_mcp_resource_templates"
    ]

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static func parseSession(from data: Data, fallbackTitle: String? = nil) throws -> CodexTranscriptSnapshot? {
        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }
        return try parseSession(from: content, fallbackTitle: fallbackTitle)
    }

    public static func parseSession(from text: String, fallbackTitle: String? = nil) throws -> CodexTranscriptSnapshot? {
        var accumulator = Accumulator(fallbackTitle: fallbackTitle)
        try accumulator.consume(text: text)
        return accumulator.snapshot()
    }

    private static func event(
        from payload: [String: JSONValue],
        sessionID: String?,
        workingDirectory: String?
    ) -> AgentEvent? {
        guard let name = stringValue(in: payload, keys: ["name"]), !name.isEmpty else {
            return nil
        }

        let arguments = parseArguments(from: payload)
        let event: AgentEvent

        switch name {
        case "exec_command":
            guard let commandEvent = eventFromExecCommand(arguments: arguments, sessionID: sessionID, workingDirectory: workingDirectory) else {
                return nil
            }
            event = commandEvent
        case "write_stdin":
            let chars = cleanedInlineText(stringValue(in: arguments, keys: ["chars"]))
            event = AgentEvent(
                kind: .runningCommand,
                hookEventName: "TranscriptToolCall",
                toolName: name,
                message: chars.flatMap { clipped($0, limit: 48) }.map { "Command: \($0)" } ?? "Command: Continue command",
                sessionID: sessionID,
                workingDirectory: workingDirectory
            )
        case "apply_patch":
            event = AgentEvent(
                kind: .editingCode,
                hookEventName: "TranscriptToolCall",
                toolName: name,
                message: "Editing: Apply patch",
                sessionID: sessionID,
                workingDirectory: workingDirectory
            )
        case "find":
            let pattern = cleanedInlineText(stringValue(in: arguments, keys: ["pattern"]))
            event = AgentEvent(
                kind: .reading,
                hookEventName: "TranscriptToolCall",
                toolName: name,
                message: pattern.flatMap { clipped($0, limit: 48) }.map { "Search: \($0)" } ?? "Search: Find",
                sessionID: sessionID,
                workingDirectory: workingDirectory
            )
        case "search_query":
            let query = searchQueryText(from: arguments) ?? "Search"
            event = AgentEvent(
                kind: .reading,
                hookEventName: "TranscriptToolCall",
                toolName: name,
                message: "Search: \(query)",
                sessionID: sessionID,
                workingDirectory: workingDirectory
            )
        case "open":
            let refID = stringValue(in: arguments, keys: ["ref_id"])
            let file = refID.flatMap(lastPathLikeComponent)
            event = AgentEvent(
                kind: .reading,
                hookEventName: "TranscriptToolCall",
                toolName: name,
                message: file.map { "File: \($0)" } ?? "File: Opened item",
                sessionID: sessionID,
                workingDirectory: workingDirectory
            )
        case "read_mcp_resource":
            let uri = stringValue(in: arguments, keys: ["uri"])
            let file = uri.flatMap(lastPathLikeComponent)
            event = AgentEvent(
                kind: .reading,
                hookEventName: "TranscriptToolCall",
                toolName: name,
                message: file.map { "File: \($0)" } ?? "File: Resource",
                sessionID: sessionID,
                workingDirectory: workingDirectory
            )
        default:
            let kind: AgentEventKind
            if editTools.contains(name) {
                kind = .editingCode
            } else if runTools.contains(name) {
                kind = .runningCommand
            } else if readTools.contains(name) {
                kind = .reading
            } else {
                kind = .thinking
            }

            event = AgentEvent(
                kind: kind,
                hookEventName: "TranscriptToolCall",
                toolName: name,
                message: humanizedToolName(name),
                sessionID: sessionID,
                workingDirectory: workingDirectory
            )
        }

        return event
    }

    private static func eventFromExecCommand(
        arguments: [String: JSONValue],
        sessionID: String?,
        workingDirectory: String?
    ) -> AgentEvent? {
        let command = cleanedInlineText(stringValue(in: arguments, keys: ["cmd"])) ?? "command"

        if shouldIgnoreCommand(command) {
            return nil
        }

        if let pattern = searchPattern(in: command) {
            return AgentEvent(
                kind: .reading,
                hookEventName: "TranscriptToolCall",
                toolName: "exec_command",
                message: "Search: \(pattern)",
                sessionID: sessionID,
                workingDirectory: workingDirectory
            )
        }

        if let file = readTarget(in: command) {
            return AgentEvent(
                kind: .reading,
                hookEventName: "TranscriptToolCall",
                toolName: "exec_command",
                message: "File: \(file)",
                sessionID: sessionID,
                workingDirectory: workingDirectory
            )
        }

        return AgentEvent(
            kind: .runningCommand,
            hookEventName: "TranscriptToolCall",
            toolName: "exec_command",
            message: "Command: \(clipped(command, limit: 72) ?? command)",
            sessionID: sessionID,
            workingDirectory: workingDirectory
        )
    }

    private static func parseArguments(from payload: [String: JSONValue]) -> [String: JSONValue] {
        if let string = stringValue(in: payload, keys: ["arguments"]),
           let value = try? JSONDecoder().decode(JSONValue.self, from: Data(string.utf8)),
           let object = value.objectValue {
            return object
        }
        return [:]
    }

    private static func dateValue(in object: [String: JSONValue], key: String) -> Date? {
        guard let text = object[key]?.stringValue else {
            return nil
        }
        return iso8601Formatter.date(from: text)
    }

    private static func stringValue(in object: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key]?.stringValue, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func parentSessionID(in payload: [String: JSONValue]) -> String? {
        subagentThreadSpawn(in: payload).flatMap {
            stringValue(in: $0, keys: ["parent_thread_id", "parentThreadID", "parent_id"])
        }
    }

    private static func subagentThreadSpawn(in payload: [String: JSONValue]) -> [String: JSONValue]? {
        guard let source = payload["source"]?.objectValue,
              let subagent = source["subagent"]?.objectValue,
              let threadSpawn = subagent["thread_spawn"]?.objectValue else {
            return nil
        }
        return threadSpawn
    }

    private static func messageText(from payload: [String: JSONValue]) -> String? {
        guard let content = payload["content"]?.arrayValue else {
            return nil
        }

        for item in content {
            guard let object = item.objectValue,
                  let text = stringValue(in: object, keys: ["text"]) else {
                continue
            }
            return text
        }
        return nil
    }

    private static func subagentNotification(from text: String) -> SubagentNotification? {
        guard let openRange = text.range(of: "<subagent_notification>"),
              let closeRange = text.range(of: "</subagent_notification>", range: openRange.upperBound..<text.endIndex) else {
            return nil
        }

        let jsonText = text[openRange.upperBound..<closeRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(jsonText.utf8)),
              let object = value.objectValue,
              let sessionID = stringValue(in: object, keys: ["agent_path"]) else {
            return nil
        }

        let summary: String?
        if let status = object["status"]?.objectValue {
            summary = stringValue(in: status, keys: ["completed", "failed", "cancelled", "status"])
        } else {
            summary = nil
        }

        return SubagentNotification(
            sessionID: sessionID,
            summary: clipped(cleanedInlineText(summary), limit: 96) ?? "Completed"
        )
    }

    private static func cleanedInlineText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func cleanedUserLine(from value: String?) -> String? {
        guard var text = cleanedInlineText(value) else {
            return nil
        }

        if let promptRange = text.range(of: "❯ ", options: .backwards) {
            text = String(text[promptRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if text.contains("") || text.contains("❯") || text.contains("") {
            return nil
        }

        if text.hasPrefix("# AGENTS.md instructions") || text.hasPrefix("<INSTRUCTIONS>") {
            return nil
        }

        if text.hasPrefix("open .build/ClawdPal.app")
            || text.hasPrefix(".build/ClawdPal.app/Contents/MacOS/ClawdPalSetup") {
            return nil
        }

        return text.isEmpty ? nil : text
    }

    private static func clipped(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        guard value.count > limit else { return value }
        return "\(value.prefix(limit - 1))..."
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.some(let lhs), .some(let rhs)):
            return max(lhs, rhs)
        case (.some(let lhs), .none):
            return lhs
        case (.none, .some(let rhs)):
            return rhs
        case (.none, .none):
            return nil
        }
    }

    private static func searchQueryText(from arguments: [String: JSONValue]) -> String? {
        if let queries = arguments["search_query"]?.arrayValue {
            for query in queries {
                if let object = query.objectValue,
                   let text = stringValue(in: object, keys: ["q"]) {
                    return clipped(cleanedInlineText(text), limit: 48)
                }
            }
        }
        return clipped(cleanedInlineText(stringValue(in: arguments, keys: ["q", "query"])), limit: 48)
    }

    private static func readTarget(in command: String) -> String? {
        let firstToken = shellTokens(from: command).first?.lowercased()
        guard let firstToken, readOnlyCommands.contains(firstToken) else {
            return nil
        }

        let tokens = shellTokens(from: command).dropFirst()
        for token in tokens.reversed() {
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !cleaned.isEmpty, !cleaned.hasPrefix("-") else { continue }
            if cleaned.contains("/") || cleaned.contains(".") || cleaned.hasPrefix("~") {
                return lastPathLikeComponent(cleaned)
            }
        }

        return nil
    }

    private static func searchPattern(in command: String) -> String? {
        let tokens = shellTokens(from: command)
        guard let firstToken = tokens.first?.lowercased() else {
            return nil
        }

        if !searchCommands.contains(firstToken) && !command.contains(" rg ") && !command.contains(" grep ") {
            return nil
        }

        if let quoted = quotedValue(in: command) {
            return clipped(quoted, limit: 48)
        }

        for token in tokens.dropFirst() {
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !cleaned.isEmpty, !cleaned.hasPrefix("-"), !cleaned.contains("/"), !cleaned.contains(".") else {
                continue
            }
            return clipped(cleaned, limit: 48)
        }

        return "Search"
    }

    private static func quotedValue(in command: String) -> String? {
        let patterns = ["\"([^\"]+)\"", "'([^']+)'"]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(command.startIndex..<command.endIndex, in: command)
            guard let match = regex.firstMatch(in: command, range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: command) else {
                continue
            }
            let value = String(command[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func shellTokens(from command: String) -> [String] {
        cleanedInlineText(command)?
            .split(whereSeparator: \.isWhitespace)
            .map(String.init) ?? []
    }

    private static func shouldIgnoreCommand(_ command: String) -> Bool {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)

        if ignoredCommandPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }

        if normalized.contains(".codex/sessions/")
            || normalized.contains(".codex/archived_sessions/")
            || normalized.contains(".codex/session_index.jsonl") {
            return true
        }

        return false
    }

    private static func lastPathLikeComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let normalized = trimmed.replacingOccurrences(of: "file://", with: "")
        let component = URL(fileURLWithPath: normalized).lastPathComponent
        return component.isEmpty ? normalized : component
    }

    private static func humanizedToolName(_ name: String) -> String {
        name
            .split(separator: "_")
            .map { token in
                token.prefix(1).uppercased() + token.dropFirst()
            }
            .joined(separator: " ")
    }
}
