import Foundation

public enum CodexHookDecoder {
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
        case "PermissionRequest":
            kind = .permissionRequest
        case "Stop":
            kind = .completed
        default:
            kind = message == nil ? .unknown : .thinking
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
        return nil
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
}
