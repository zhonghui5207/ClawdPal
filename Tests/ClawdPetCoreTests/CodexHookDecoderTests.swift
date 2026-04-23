import Foundation
import Testing
@testable import ClawdPetCore

struct CodexHookDecoderTests {
    @Test
    func testUserPromptSubmit() throws {
        let json = Data("""
        {"hook_event_name":"UserPromptSubmit","session_id":"demo","cwd":"/tmp/project","prompt":"continue implementation"}
        """.utf8)

        let event = try CodexHookDecoder.decodeEvent(from: json)

        #expect(event.kind == .thinking)
        #expect(event.hookEventName == "UserPromptSubmit")
        #expect(event.sessionID == "demo")
        #expect(event.workingDirectory == "/tmp/project")
        #expect(event.message == "Prompt: continue implementation")
    }

    @Test
    func testPermissionRequest() throws {
        let json = Data("""
        {"hook_event_name":"PermissionRequest","session_id":"demo"}
        """.utf8)

        let event = try CodexHookDecoder.decodeEvent(from: json)

        #expect(event.kind == .permissionRequest)
        #expect(event.hookEventName == "PermissionRequest")
        #expect(event.message == "Permission requested")
    }

    @Test
    func testStop() throws {
        let json = Data("""
        {"hook_event_name":"Stop","session_id":"demo"}
        """.utf8)

        let event = try CodexHookDecoder.decodeEvent(from: json)

        #expect(event.kind == .completed)
        #expect(event.hookEventName == "Stop")
    }

    @Test
    func testPreToolUseBash() throws {
        let json = Data("""
        {"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"demo","tool_input":{"command":"swift build"}}
        """.utf8)

        let event = try CodexHookDecoder.decodeEvent(from: json)

        #expect(event.kind == .runningCommand)
        #expect(event.hookEventName == "PreToolUse")
        #expect(event.message == "Command: swift build")
    }

    @Test
    func testPreToolUseRead() throws {
        let json = Data("""
        {"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"demo","tool_input":{"file_path":"/tmp/project/AppModel.swift"}}
        """.utf8)

        let event = try CodexHookDecoder.decodeEvent(from: json)

        #expect(event.kind == .reading)
        #expect(event.message == "File: AppModel.swift")
    }
}
