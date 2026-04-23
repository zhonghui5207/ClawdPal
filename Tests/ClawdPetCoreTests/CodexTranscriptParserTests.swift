import Foundation
import Testing
@testable import ClawdPetCore

struct CodexTranscriptParserTests {
    @Test
    func parsesExecCommandAndThreadTitle() throws {
        let text = """
        {"timestamp":"2026-04-23T06:20:32.340Z","type":"session_meta","payload":{"id":"019db8ff-3ec9-7091-8715-e7ce0be39b75","cwd":"/Users/ryan/code/ClawdPet"}}
        {"timestamp":"2026-04-23T06:20:38.546Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_id":"019db8ff-3ec9-7091-8715-e7ce0be39b75","thread_name":"修复拖动卡顿抖动"}}
        {"timestamp":"2026-04-23T06:21:10.000Z","type":"event_msg","payload":{"type":"user_message","message":"Read /Users/ryan/code/ClawdPet/README.md, then run git status"}}
        {"timestamp":"2026-04-23T06:21:12.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"sed -n '1,220p' README.md\\",\\"workdir\\":\\"/Users/ryan/code/ClawdPet\\"}","call_id":"call_demo"}}
        """

        let snapshot = try #require(try CodexTranscriptParser.parseSession(from: text))

        #expect(snapshot.sessionID == "019db8ff-3ec9-7091-8715-e7ce0be39b75")
        #expect(snapshot.taskTitle == "修复拖动卡顿抖动")
        #expect(snapshot.latestUserLine == "Read /Users/ryan/code/ClawdPet/README.md, then run git status")
        #expect(snapshot.event.kind == .reading)
        #expect(snapshot.event.message == "File: README.md")
        #expect(snapshot.event.workingDirectory == "/Users/ryan/code/ClawdPet")
    }

    @Test
    func fallsBackToPromptWhenNoToolCallExists() throws {
        let text = """
        {"timestamp":"2026-04-23T06:20:32.340Z","type":"session_meta","payload":{"id":"demo-session","cwd":"/tmp/project"}}
        {"timestamp":"2026-04-23T06:20:38.546Z","type":"event_msg","payload":{"type":"user_message","message":"继续把 transcript 方案接进面板里"}}
        """

        let snapshot = try #require(try CodexTranscriptParser.parseSession(from: text, fallbackTitle: "默认标题"))

        #expect(snapshot.taskTitle == "默认标题")
        #expect(snapshot.latestUserLine == "继续把 transcript 方案接进面板里")
        #expect(snapshot.event.kind == .thinking)
        #expect(snapshot.event.message == "Prompt: 继续把 transcript 方案接进面板里")
    }

    @Test
    func parsesSearchCommandAsReading() throws {
        let text = """
        {"timestamp":"2026-04-23T06:20:32.340Z","type":"session_meta","payload":{"id":"demo-session","cwd":"/tmp/project"}}
        {"timestamp":"2026-04-23T06:20:40.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"rg -n \\\\\\"drag\\\\\\" Sources\\",\\"workdir\\":\\"/tmp/project\\"}","call_id":"call_demo"}}
        """

        let snapshot = try #require(try CodexTranscriptParser.parseSession(from: text))

        #expect(snapshot.event.kind == .reading)
        #expect(snapshot.event.message == "Search: drag")
    }

    @Test
    func ignoresHousekeepingCommandAndKeepsLastMeaningfulAction() throws {
        let text = """
        {"timestamp":"2026-04-23T06:20:32.340Z","type":"session_meta","payload":{"id":"demo-session","cwd":"/tmp/project"}}
        {"timestamp":"2026-04-23T06:20:38.546Z","type":"event_msg","payload":{"type":"user_message","message":"继续修面板"}}        
        {"timestamp":"2026-04-23T06:20:40.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"sed -n '1,220p' README.md\\",\\"workdir\\":\\"/tmp/project\\"}","call_id":"call_demo_1"}}
        {"timestamp":"2026-04-23T06:20:42.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"git status --short\\",\\"workdir\\":\\"/tmp/project\\"}","call_id":"call_demo_2"}}
        """

        let snapshot = try #require(try CodexTranscriptParser.parseSession(from: text))

        #expect(snapshot.event.kind == .reading)
        #expect(snapshot.event.message == "File: README.md")
    }

    @Test
    func dropsTerminalPromptUserLine() throws {
        let text = """
        {"timestamp":"2026-04-23T06:20:32.340Z","type":"session_meta","payload":{"id":"demo-session","cwd":"/tmp/project"}}
        {"timestamp":"2026-04-23T06:20:38.546Z","type":"event_msg","payload":{"type":"user_message","message":"󰀵 ryan …/ClawdPet ❯ open .build/ClawdPet.app"}}
        {"timestamp":"2026-04-23T06:20:40.000Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_id":"demo-session","thread_name":"改造 Clawd 浮宠架构"}}
        """

        let snapshot = try #require(try CodexTranscriptParser.parseSession(from: text))

        #expect(snapshot.latestUserLine == nil)
        #expect(snapshot.taskTitle == "改造 Clawd 浮宠架构")
    }
}
