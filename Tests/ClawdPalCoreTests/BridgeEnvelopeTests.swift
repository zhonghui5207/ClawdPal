import Foundation
import Testing
@testable import ClawdPalCore

struct BridgeEnvelopeTests {
    @Test
    func testRoundTrip() throws {
        let envelope = BridgeEnvelope(
            source: "claude-code",
            receivedAt: Date(timeIntervalSince1970: 1_777_000_000),
            event: AgentEvent(kind: .editingCode, toolName: "Edit", sessionID: "session-1")
        )

        let data = try JSONEncoder.bridgeEncoder.encode(envelope)
        let decoded = try JSONDecoder.bridgeDecoder.decode(BridgeEnvelope.self, from: data)

        #expect(decoded == envelope)
    }
}
