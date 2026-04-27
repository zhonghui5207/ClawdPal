import Foundation
import Testing
@testable import ClawdPalCore

struct ClaudeHookSettingsTests {
    @Test
    func installAddsClawdPalHooksWithoutRemovingExistingHooks() throws {
        let directory = try temporaryDirectory()
        let settingsPath = directory.appendingPathComponent("settings.json").path
        let hookPath = try fakeExecutable(in: directory)

        try """
        {
          "theme": "dark",
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "/tmp/existing-hook"
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: settingsPath))

        let result = try ClaudeHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["PreToolUse", "Stop"]
        )

        #expect(result.backupPath != nil)
        let settings = try readSettings(settingsPath)
        let hooks = try #require(settings.objectValue?["hooks"]?.objectValue)
        let preToolGroups = try #require(hooks["PreToolUse"]?.arrayValue)
        let stopGroups = try #require(hooks["Stop"]?.arrayValue)

        #expect(preToolGroups.count == 2)
        #expect(stopGroups.count == 1)
        #expect(preToolGroups.contains { containsCommand($0, "/tmp/existing-hook") })
        #expect(preToolGroups.contains { containsCommand($0, "ClawdPalHooks") })
    }

    @Test
    func reinstallReplacesExistingClawdPalHookGroup() throws {
        let directory = try temporaryDirectory()
        let settingsPath = directory.appendingPathComponent("settings.json").path
        let hookPath = try fakeExecutable(in: directory)

        _ = try ClaudeHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["PreToolUse"]
        )
        _ = try ClaudeHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["PreToolUse"]
        )

        let settings = try readSettings(settingsPath)
        let hooks = try #require(settings.objectValue?["hooks"]?.objectValue)
        let groups = try #require(hooks["PreToolUse"]?.arrayValue)

        #expect(groups.filter { containsCommand($0, "ClawdPalHooks") }.count == 1)
    }

    @Test
    func installReplacesLegacyClawdPetHookGroup() throws {
        let directory = try temporaryDirectory()
        let settingsPath = directory.appendingPathComponent("settings.json").path
        let hookPath = try fakeExecutable(in: directory)

        try """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "*",
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/tmp/ClawdPetHooks' --source claude"
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: settingsPath))

        _ = try ClaudeHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["PreToolUse"]
        )

        let settings = try readSettings(settingsPath)
        let hooks = try #require(settings.objectValue?["hooks"]?.objectValue)
        let groups = try #require(hooks["PreToolUse"]?.arrayValue)

        #expect(groups.count == 1)
        #expect(groups.contains { containsCommand($0, "ClawdPalHooks") })
        #expect(!groups.contains { containsCommand($0, "ClawdPetHooks") })
    }

    @Test
    func installRemovesStaleClawdPalHooksFromUnwantedEvents() throws {
        let directory = try temporaryDirectory()
        let settingsPath = directory.appendingPathComponent("settings.json").path
        let hookPath = try fakeExecutable(in: directory)

        try """
        {
          "hooks": {
            "SessionStart": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/tmp/ClawdPalHooks' --source claude"
                  }
                ]
              },
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/tmp/existing-session-start-hook"
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: settingsPath))

        _ = try ClaudeHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["PreToolUse"]
        )

        let settings = try readSettings(settingsPath)
        let hooks = try #require(settings.objectValue?["hooks"]?.objectValue)
        let sessionStartGroups = try #require(hooks["SessionStart"]?.arrayValue)

        #expect(sessionStartGroups.count == 1)
        #expect(sessionStartGroups.contains { containsCommand($0, "/tmp/existing-session-start-hook") })
        #expect(!sessionStartGroups.contains { containsCommand($0, "ClawdPalHooks") })
    }

    @Test
    func uninstallRemovesOnlyClawdPalHooks() throws {
        let directory = try temporaryDirectory()
        let settingsPath = directory.appendingPathComponent("settings.json").path
        let hookPath = try fakeExecutable(in: directory)

        try """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "/tmp/existing-hook"
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: settingsPath))

        _ = try ClaudeHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["PreToolUse", "Stop"]
        )
        let result = try ClaudeHookSettings.uninstall(settingsPath: settingsPath)

        #expect(result.installedEvents == ["PreToolUse", "Stop"])
        let settings = try readSettings(settingsPath)
        let hooks = try #require(settings.objectValue?["hooks"]?.objectValue)
        let preToolGroups = try #require(hooks["PreToolUse"]?.arrayValue)

        #expect(preToolGroups.count == 1)
        #expect(preToolGroups.contains { containsCommand($0, "/tmp/existing-hook") })
        #expect(hooks["Stop"] == nil)
    }

    @Test
    func isInstalledTracksClawdPalHooksAcrossExpectedEvents() throws {
        let directory = try temporaryDirectory()
        let settingsPath = directory.appendingPathComponent("settings.json").path
        let hookPath = try fakeExecutable(in: directory)

        #expect(try ClaudeHookSettings.isInstalled(settingsPath: settingsPath, events: ["PreToolUse"]) == false)

        _ = try ClaudeHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["PreToolUse", "Stop"]
        )

        #expect(try ClaudeHookSettings.isInstalled(settingsPath: settingsPath, events: ["PreToolUse", "Stop"]) == true)
        #expect(try ClaudeHookSettings.isInstalled(settingsPath: settingsPath, events: ["PreToolUse", "Stop", "SessionStart"]) == false)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClawdPalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fakeExecutable(in directory: URL) throws -> String {
        let url = directory.appendingPathComponent("ClawdPalHooks")
        try "#!/bin/sh\nexit 0\n".data(using: .utf8)!.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func readSettings(_ path: String) throws -> JSONValue {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func containsCommand(_ group: JSONValue, _ needle: String) -> Bool {
        guard let hooks = group.objectValue?["hooks"]?.arrayValue else {
            return false
        }

        return hooks.contains { hook in
            guard case .string(let command)? = hook.objectValue?["command"] else {
                return false
            }
            return command.contains(needle)
        }
    }
}
