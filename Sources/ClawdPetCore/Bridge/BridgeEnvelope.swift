import Foundation

public struct BridgeEnvelope: Codable, Equatable, Sendable {
    public var source: String
    public var receivedAt: Date
    public var event: AgentEvent

    public init(source: String, receivedAt: Date = Date(), event: AgentEvent) {
        self.source = source
        self.receivedAt = receivedAt
        self.event = event
    }
}
