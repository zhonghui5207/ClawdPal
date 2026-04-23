import Foundation

public enum AgentEventKind: String, Codable, Equatable, Sendable {
    case idle
    case thinking
    case reading
    case runningCommand
    case editingCode
    case completed
    case unknown
}

public struct AgentEvent: Codable, Equatable, Sendable {
    public var kind: AgentEventKind
    public var toolName: String?
    public var message: String?
    public var sessionID: String?
    public var workingDirectory: String?

    public init(
        kind: AgentEventKind,
        toolName: String? = nil,
        message: String? = nil,
        sessionID: String? = nil,
        workingDirectory: String? = nil
    ) {
        self.kind = kind
        self.toolName = toolName
        self.message = message
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
    }
}
