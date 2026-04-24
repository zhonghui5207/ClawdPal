import Foundation
import Testing
@testable import ClawdPalCore

struct CodexHookSettingsTests {
    @Test
    func installAddsClawdPalHooksWithoutRemovingVibeIslandHooks() throws {
        let directory = try temporaryDirectory()
        let settingsPath = directory.appendingPathComponent("hooks.json").path
        let hookPath = try fakeExecutable(in: directory)

        try """
        {
          "hooks": {
            "UserPromptSubmit": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/Users/ryan/.vibe-island/bin/vibe-island-bridge' --source codex",
                    "timeout": 5
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: settingsPath))

        _ = try CodexHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["UserPromptSubmit"]
        )

        let settings = try readSettings(settingsPath)
        let hooks = try #require(settings.objectValue?["hooks"]?.objectValue)
        let groups = try #require(hooks["UserPromptSubmit"]?.arrayValue)

        #expect(groups.count == 2)
        #expect(groups.contains { containsCommand($0, "vibe-island-bridge") })
        #expect(groups.contains { containsCommand($0, "ClawdPalHooks") })
    }

    @Test
    func reinstallDoesNotDuplicateClawdPalHook() throws {
        let directory = try temporaryDirectory()
        let settingsPath = directory.appendingPathComponent("hooks.json").path
        let hookPath = try fakeExecutable(in: directory)

        _ = try CodexHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["Stop"]
        )
        _ = try CodexHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["Stop"]
        )

        let settings = try readSettings(settingsPath)
        let hooks = try #require(settings.objectValue?["hooks"]?.objectValue)
        let groups = try #require(hooks["Stop"]?.arrayValue)

        #expect(groups.filter { containsCommand($0, "ClawdPalHooks") }.count == 1)
    }

    @Test
    func installReplacesLegacyClawdPetHook() throws {
        let directory = try temporaryDirectory()
        let settingsPath = directory.appendingPathComponent("hooks.json").path
        let hookPath = try fakeExecutable(in: directory)

        try """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/tmp/ClawdPetHooks' --source codex",
                    "timeout": 5
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: settingsPath))

        _ = try CodexHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["Stop"]
        )

        let settings = try readSettings(settingsPath)
        let hooks = try #require(settings.objectValue?["hooks"]?.objectValue)
        let groups = try #require(hooks["Stop"]?.arrayValue)

        #expect(groups.count == 1)
        #expect(groups.contains { containsCommand($0, "ClawdPalHooks") })
        #expect(!groups.contains { containsCommand($0, "ClawdPetHooks") })
    }

    @Test
    func uninstallRemovesOnlyClawdPalHooks() throws {
        let directory = try temporaryDirectory()
        let settingsPath = directory.appendingPathComponent("hooks.json").path
        let hookPath = try fakeExecutable(in: directory)

        try """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/Users/ryan/.vibe-island/bin/vibe-island-bridge' --source codex",
                    "timeout": 5
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: settingsPath))

        _ = try CodexHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["Stop"]
        )
        _ = try CodexHookSettings.uninstall(settingsPath: settingsPath)

        let settings = try readSettings(settingsPath)
        let hooks = try #require(settings.objectValue?["hooks"]?.objectValue)
        let groups = try #require(hooks["Stop"]?.arrayValue)

        #expect(groups.count == 1)
        #expect(groups.contains { containsCommand($0, "vibe-island-bridge") })
        #expect(!groups.contains { containsCommand($0, "ClawdPalHooks") })
    }

    @Test
    func isInstalledTracksCodexHooksAcrossExpectedEvents() throws {
        let directory = try temporaryDirectory()
        let settingsPath = directory.appendingPathComponent("hooks.json").path
        let hookPath = try fakeExecutable(in: directory)

        #expect(try CodexHookSettings.isInstalled(settingsPath: settingsPath, events: ["Stop"]) == false)

        _ = try CodexHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath,
            events: ["SessionStart", "Stop"]
        )

        #expect(try CodexHookSettings.isInstalled(settingsPath: settingsPath, events: ["SessionStart", "Stop"]) == true)
        #expect(try CodexHookSettings.isInstalled(settingsPath: settingsPath, events: ["SessionStart", "UserPromptSubmit", "Stop"]) == false)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClawdPalCodexTests-\(UUID().uuidString)")
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
