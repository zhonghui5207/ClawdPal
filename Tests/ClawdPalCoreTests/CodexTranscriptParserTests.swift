import Foundation
import Testing
@testable import ClawdPalCore

struct CodexTranscriptParserTests {
    @Test
    func parsesExecCommandAndThreadTitle() throws {
        let text = """
        {"timestamp":"2026-04-23T06:20:32.340Z","type":"session_meta","payload":{"id":"019db8ff-3ec9-7091-8715-e7ce0be39b75","cwd":"/Users/ryan/code/ClawdPal"}}
        {"timestamp":"2026-04-23T06:20:38.546Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_id":"019db8ff-3ec9-7091-8715-e7ce0be39b75","thread_name":"修复拖动卡顿抖动"}}
        {"timestamp":"2026-04-23T06:21:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"timestamp":"2026-04-23T06:21:10.000Z","type":"event_msg","payload":{"type":"user_message","message":"Read /Users/ryan/code/ClawdPal/README.md, then run git status"}}
        {"timestamp":"2026-04-23T06:21:12.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"sed -n '1,220p' README.md\\",\\"workdir\\":\\"/Users/ryan/code/ClawdPal\\"}","call_id":"call_demo"}}
        """

        let snapshot = try #require(try CodexTranscriptParser.parseSession(from: text))

        #expect(snapshot.sessionID == "019db8ff-3ec9-7091-8715-e7ce0be39b75")
        #expect(snapshot.taskTitle == "修复拖动卡顿抖动")
        #expect(snapshot.latestUserLine == "Read /Users/ryan/code/ClawdPal/README.md, then run git status")
        #expect(snapshot.event.kind == .reading)
        #expect(snapshot.event.message == "File: README.md")
        #expect(snapshot.event.workingDirectory == "/Users/ryan/code/ClawdPal")
    }

    @Test
    func fallsBackToPromptWhenNoToolCallExists() throws {
        let text = """
        {"timestamp":"2026-04-23T06:20:32.340Z","type":"session_meta","payload":{"id":"demo-session","cwd":"/tmp/project"}}
        {"timestamp":"2026-04-23T06:20:36.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
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
        {"timestamp":"2026-04-23T06:20:36.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
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
        {"timestamp":"2026-04-23T06:20:36.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
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
        {"timestamp":"2026-04-23T06:20:36.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"timestamp":"2026-04-23T06:20:38.546Z","type":"event_msg","payload":{"type":"user_message","message":"󰀵 ryan …/ClawdPal ❯ open .build/ClawdPal.app"}}
        {"timestamp":"2026-04-23T06:20:40.000Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_id":"demo-session","thread_name":"改造 Clawd 浮宠架构"}}
        """

        let snapshot = try #require(try CodexTranscriptParser.parseSession(from: text))

        #expect(snapshot.latestUserLine == nil)
        #expect(snapshot.taskTitle == "改造 Clawd 浮宠架构")
    }

    @Test
    func activityCutoffDoesNotRestoreOldCompletedTurns() throws {
        let cutoff = try #require(Self.date("2026-04-23T06:21:00.000Z"))
        let text = """
        {"timestamp":"2026-04-23T06:20:32.340Z","type":"session_meta","payload":{"id":"demo-session","cwd":"/tmp/project"}}
        {"timestamp":"2026-04-23T06:20:36.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"timestamp":"2026-04-23T06:20:38.000Z","type":"event_msg","payload":{"type":"user_message","message":"old completed turn"}}
        {"timestamp":"2026-04-23T06:20:40.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}
        """

        var accumulator = CodexTranscriptParser.Accumulator(activityCutoff: cutoff)
        try accumulator.consume(text: text)
        let snapshot = try #require(accumulator.snapshot())

        #expect(snapshot.event.kind == .idle)
        #expect(snapshot.latestUserLine == nil)
    }

    @Test
    func activityCutoffKeepsNewCompletedTurns() throws {
        let cutoff = try #require(Self.date("2026-04-23T06:21:00.000Z"))
        let text = """
        {"timestamp":"2026-04-23T06:20:32.340Z","type":"session_meta","payload":{"id":"demo-session","cwd":"/tmp/project"}}
        {"timestamp":"2026-04-23T06:21:02.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"timestamp":"2026-04-23T06:21:04.000Z","type":"event_msg","payload":{"type":"user_message","message":"new completed turn"}}
        {"timestamp":"2026-04-23T06:21:06.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}
        """

        var accumulator = CodexTranscriptParser.Accumulator(activityCutoff: cutoff)
        try accumulator.consume(text: text)
        let snapshot = try #require(accumulator.snapshot())

        #expect(snapshot.event.kind == .completed)
        #expect(snapshot.latestUserLine == "new completed turn")
    }

    @Test
    func parsesSubagentParentMetadata() throws {
        let text = """
        {"timestamp":"2026-04-24T06:13:42.936Z","type":"session_meta","payload":{"id":"child-session","timestamp":"2026-04-24T06:13:41.246Z","cwd":"/tmp/project","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent-session","depth":1,"agent_nickname":"Kepler","agent_role":"explorer"}}}}}
        {"timestamp":"2026-04-24T06:13:43.000Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_id":"child-session","thread_name":"Summarize UI flow"}}
        {"timestamp":"2026-04-24T06:13:44.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"timestamp":"2026-04-24T06:13:45.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"sed -n '1,80p' Sources/ClawdPalApp/AppModel.swift\\",\\"workdir\\":\\"/tmp/project\\"}","call_id":"call_demo"}}
        """

        let snapshot = try #require(try CodexTranscriptParser.parseSession(from: text))

        #expect(snapshot.sessionID == "child-session")
        #expect(snapshot.parentSessionID == "parent-session")
        #expect(snapshot.subagentName == "Kepler")
        #expect(snapshot.subagentRole == "explorer")
        #expect(snapshot.isSubagent)
        #expect(snapshot.taskTitle == "Summarize UI flow")
        #expect(snapshot.event.kind == .reading)
    }

    @Test
    func parsesParentSpawnedSubagentsAndNotifications() throws {
        let text = """
        {"timestamp":"2026-04-24T06:27:20.000Z","type":"session_meta","payload":{"id":"parent-session","cwd":"/tmp/project"}}
        {"timestamp":"2026-04-24T06:27:21.000Z","type":"event_msg","payload":{"type":"collab_agent_spawn_end","sender_thread_id":"parent-session","new_thread_id":"child-a","new_agent_nickname":"Tesla","new_agent_role":"explorer","prompt":"Read-only check for parser"}}
        {"timestamp":"2026-04-24T06:27:22.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<subagent_notification>\\n{\\"agent_path\\":\\"child-a\\",\\"status\\":{\\"completed\\":\\"Read-only inspection complete. No files edited.\\"}}\\n</subagent_notification>"}]}}
        """

        let snapshot = try #require(try CodexTranscriptParser.parseSession(from: text))
        let subagent = try #require(snapshot.subagents.first)

        #expect(snapshot.sessionID == "parent-session")
        #expect(subagent.sessionID == "child-a")
        #expect(subagent.parentSessionID == "parent-session")
        #expect(subagent.name == "Tesla")
        #expect(subagent.role == "explorer")
        #expect(subagent.taskTitle == "Read-only check for parser")
        #expect(subagent.latestSummary == "Read-only inspection complete. No files edited.")
        #expect(subagent.kind == .completed)
    }

    @Test
    func parsesSubagentShutdownNotification() throws {
        let text = """
        {"timestamp":"2026-04-24T06:27:20.000Z","type":"session_meta","payload":{"id":"parent-session","cwd":"/tmp/project"}}
        {"timestamp":"2026-04-24T06:27:21.000Z","type":"event_msg","payload":{"type":"collab_agent_spawn_end","sender_thread_id":"parent-session","new_thread_id":"child-a","new_agent_nickname":"Tesla","new_agent_role":"explorer","prompt":"Read-only check for parser"}}
        {"timestamp":"2026-04-24T06:27:22.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<subagent_notification>\\n{\\"agent_path\\":\\"child-a\\",\\"status\\":\\"shutdown\\"}\\n</subagent_notification>"}]}}
        """

        let snapshot = try #require(try CodexTranscriptParser.parseSession(from: text))
        let subagent = try #require(snapshot.subagents.first)

        #expect(subagent.sessionID == "child-a")
        #expect(subagent.latestSummary == "shutdown")
        #expect(subagent.kind == .completed)
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}
