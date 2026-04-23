import Foundation

public enum CodexHookDecoder {
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
        let payload = try JSONDecoder().decode(JSONValue.self, from: data)
        return event(from: payload)
    }

    public static func event(from payload: JSONValue) -> AgentEvent {
        let object = payload.objectValue ?? [:]
        let hookName = stringValue(in: object, keys: ["hook_event_name", "hookEventName", "event", "name"]) ?? ""
        let toolName = stringValue(in: object, keys: ["tool_name", "toolName", "tool"])
        let message = summary(from: object, hookName: hookName)

        let kind: AgentEventKind
        switch hookName {
        case "SessionStart":
            kind = .idle
        case "UserPromptSubmit":
            kind = .thinking
        case "PreToolUse":
            kind = kindForTool(toolName)
        case "PostToolUse":
            kind = .thinking
        case "PostToolUseFailure":
            kind = .error
        case "PermissionRequest":
            kind = .permissionRequest
        case "Stop":
            kind = .completed
        default:
            kind = toolName.map(kindForTool) ?? (message == nil ? .unknown : .thinking)
        }

        return AgentEvent(
            kind: kind,
            hookEventName: hookName.isEmpty ? nil : hookName,
            toolName: toolName,
            message: message,
            sessionID: stringValue(in: object, keys: ["session_id", "sessionID", "sessionId", "conversation_id"]),
            workingDirectory: stringValue(in: object, keys: ["cwd", "working_directory", "workingDirectory"])
        )
    }

    private static func summary(from object: [String: JSONValue], hookName: String) -> String? {
        if let message = stringValue(in: object, keys: ["message", "summary"]) {
            return clipped(message)
        }
        if hookName == "UserPromptSubmit",
           let prompt = stringValue(in: object, keys: ["prompt", "user_prompt", "userPrompt"]) {
            return "Prompt: \(clipped(prompt))"
        }
        if hookName == "PermissionRequest" {
            return "Permission requested"
        }
        if hookName == "SessionStart" {
            return "Session started"
        }
        if hookName == "Stop" {
            return "Done."
        }

        guard let toolInput = object["tool_input"]?.objectValue ?? object["toolInput"]?.objectValue else {
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

        return nil
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

    private static func stringValue(in object: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key]?.stringValue, !value.isEmpty {
                return value
            }
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
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent.isEmpty ? path : url.lastPathComponent
    }
}
