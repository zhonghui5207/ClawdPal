import Foundation

public enum ClaudeHookDecoder {
    private static let readingTools: Set<String> = [
        "Read", "LS", "Glob", "Grep", "Search", "WebFetch", "WebSearch"
    ]

    private static let commandTools: Set<String> = [
        "Bash", "Shell"
    ]

    private static let editingTools: Set<String> = [
        "Edit", "Write", "MultiEdit", "NotebookEdit"
    ]

    public static func decodeEvent(from data: Data) throws -> AgentEvent {
        let payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: data)
        return event(from: payload)
    }

    public static func event(from payload: ClaudeHookPayload) -> AgentEvent {
        let hookName = payload.hookEventName ?? ""
        let toolName = payload.toolName
        let kind: AgentEventKind

        switch hookName {
        case "UserPromptSubmit", "Notification":
            kind = .thinking
        case "PermissionRequest":
            kind = .permissionRequest
        case "PermissionDenied":
            kind = .error
        case "SessionStart":
            kind = .idle
        case "SessionEnd":
            kind = .completed
        case "PreToolUse":
            kind = kindForTool(toolName)
        case "PostToolUse":
            kind = .thinking
        case "PostToolUseFailure":
            kind = .error
        case "SubagentStart", "TaskCreated":
            kind = .thinking
        case "TaskCompleted":
            kind = .completed
        case "CwdChanged":
            kind = .reading
        case "Stop", "SubagentStop":
            kind = .completed
        case "StopFailure":
            kind = .error
        default:
            kind = toolName.map(kindForTool) ?? .unknown
        }

        return AgentEvent(
            kind: kind,
            hookEventName: hookName.isEmpty ? nil : hookName,
            toolName: toolName,
            message: summary(from: payload, fallbackKind: kind),
            sessionID: payload.sessionID,
            workingDirectory: payload.cwd
        )
    }

    private static func kindForTool(_ toolName: String?) -> AgentEventKind {
        guard let toolName else {
            return .thinking
        }
        if readingTools.contains(toolName) {
            return .reading
        }
        if commandTools.contains(toolName) {
            return .runningCommand
        }
        if editingTools.contains(toolName) {
            return .editingCode
        }
        return .thinking
    }

    private static func summary(from payload: ClaudeHookPayload, fallbackKind: AgentEventKind) -> String? {
        if let message = payload.message, !message.isEmpty {
            return clipped(message)
        }

        switch payload.hookEventName {
        case "UserPromptSubmit":
            return payload.prompt.map { "Prompt: \(clipped($0))" }
        case "Notification":
            return payload.notificationType.map { "Notification: \($0)" }
        case "PermissionRequest":
            return "Permission requested"
        case "PermissionDenied":
            return "Permission denied"
        case "SessionStart":
            return payload.source.map { "Session started: \($0)" } ?? "Session started"
        case "SessionEnd":
            return payload.reason.map { "Session ended: \($0)" } ?? "Session ended"
        case "CwdChanged":
            return payload.cwd.map { "Directory: \(lastPathComponent($0))" }
        default:
            break
        }

        guard let toolInput = payload.toolInput?.objectValue else {
            return nil
        }

        if let command = toolInput["command"]?.stringValue {
            return "Command: \(clipped(command))"
        }
        if let filePath = toolInput["file_path"]?.stringValue ?? toolInput["path"]?.stringValue {
            return "File: \(lastPathComponent(filePath))"
        }
        if let pattern = toolInput["pattern"]?.stringValue {
            return "Search: \(clipped(pattern))"
        }
        if fallbackKind == .editingCode, let oldString = toolInput["old_string"]?.stringValue {
            return "Editing: \(clipped(oldString))"
        }
        return nil
    }

    private static func clipped(_ value: String, limit: Int = 72) -> String {
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else {
            return normalized
        }
        return "\(normalized.prefix(limit - 1))..."
    }

    private static func lastPathComponent(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent.isEmpty ? path : URL(fileURLWithPath: path).lastPathComponent
    }
}
