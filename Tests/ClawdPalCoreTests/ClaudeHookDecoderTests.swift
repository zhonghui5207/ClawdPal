import Foundation
import Testing
@testable import ClawdPalCore

struct ClaudeHookDecoderTests {
    @Test
    func testPreToolReadEvent() throws {
        let json = Data("""
        {"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"demo","cwd":"/tmp/project"}
        """.utf8)

        let event = try ClaudeHookDecoder.decodeEvent(from: json)

        #expect(event.kind == .reading)
        #expect(event.hookEventName == "PreToolUse")
        #expect(event.toolName == "Read")
        #expect(event.sessionID == "demo")
        #expect(event.workingDirectory == "/tmp/project")
    }

    @Test
    func testPreToolBashEvent() throws {
        let json = Data("""
        {"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"demo","tool_input":{"command":"npm test -- --filter core"}}
        """.utf8)

        let event = try ClaudeHookDecoder.decodeEvent(from: json)

        #expect(event.kind == .runningCommand)
        #expect(event.message == "Command: npm test -- --filter core")
    }

    @Test
    func testStopEvent() throws {
        let json = Data("""
        {"hook_event_name":"Stop","session_id":"demo"}
        """.utf8)

        let event = try ClaudeHookDecoder.decodeEvent(from: json)

        #expect(event.kind == .completed)
        #expect(event.hookEventName == "Stop")
    }

    @Test
    func testUserPromptSubmitUsesPromptSummary() throws {
        let json = Data("""
        {"hook_event_name":"UserPromptSubmit","session_id":"demo","prompt":"continue building the floating pet"}
        """.utf8)

        let event = try ClaudeHookDecoder.decodeEvent(from: json)

        #expect(event.kind == .thinking)
        #expect(event.hookEventName == "UserPromptSubmit")
        #expect(event.message == "Prompt: continue building the floating pet")
    }
}
