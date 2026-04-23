import Foundation

public struct ClaudeHookPayload: Codable, Equatable, Sendable {
    public var hookEventName: String?
    public var sessionID: String?
    public var transcriptPath: String?
    public var cwd: String?
    public var toolName: String?
    public var toolInput: JSONValue?
    public var message: String?
    public var prompt: String?
    public var notificationType: String?
    public var source: String?
    public var reason: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case message
        case prompt
        case notificationType = "notification_type"
        case source
        case reason
    }
}
