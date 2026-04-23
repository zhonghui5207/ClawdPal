import Foundation

public enum CodexHookSettings {
    public static let clawdPetMarker = "ClawdPetHooks"

    public static let defaultEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "PermissionRequest",
        "Stop"
    ]

    public static var defaultSettingsPath: String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.codex/hooks.json"
    }

    public static func install(
        settingsPath: String = defaultSettingsPath,
        hookBinaryPath: String,
        events: [String] = defaultEvents
    ) throws -> ClaudeHookInstallResult {
        guard FileManager.default.isExecutableFile(atPath: hookBinaryPath) else {
            throw ClaudeHookSettingsError.hookBinaryMissing(hookBinaryPath)
        }

        var settings = try readSettings(at: settingsPath)
        guard case .object(var root) = settings else {
            throw ClaudeHookSettingsError.invalidSettingsRoot
        }

        let backupPath = try backupIfNeeded(settingsPath)
        let hooksValue = root["hooks"] ?? .object([:])
        guard case .object(var hooksObject) = hooksValue else {
            throw ClaudeHookSettingsError.invalidHooksRoot
        }

        for event in events {
            let existingGroups = hooksObject[event]?.arrayValue ?? []
            let cleanedGroups = existingGroups.filter { !containsClawdPetHook($0) }
            hooksObject[event] = .array(cleanedGroups + [hookGroup(hookBinaryPath: hookBinaryPath)])
        }

        root["hooks"] = .object(hooksObject)
        settings = .object(root)
        try write(settings, to: settingsPath)

        return ClaudeHookInstallResult(
            settingsPath: settingsPath,
            backupPath: backupPath,
            installedEvents: events
        )
    }

    public static func uninstall(settingsPath: String = defaultSettingsPath) throws -> ClaudeHookInstallResult {
        var settings = try readSettings(at: settingsPath)
        guard case .object(var root) = settings else {
            throw ClaudeHookSettingsError.invalidSettingsRoot
        }

        let backupPath = try backupIfNeeded(settingsPath)
        guard case .object(var hooksObject) = root["hooks"] ?? .object([:]) else {
            throw ClaudeHookSettingsError.invalidHooksRoot
        }

        var touchedEvents: [String] = []
        for (event, value) in hooksObject {
            guard let groups = value.arrayValue else { continue }
            let cleanedGroups = groups.filter { !containsClawdPetHook($0) }
            if cleanedGroups.count != groups.count {
                touchedEvents.append(event)
                if cleanedGroups.isEmpty {
                    hooksObject.removeValue(forKey: event)
                } else {
                    hooksObject[event] = .array(cleanedGroups)
                }
            }
        }

        if hooksObject.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = .object(hooksObject)
        }

        settings = .object(root)
        try write(settings, to: settingsPath)

        return ClaudeHookInstallResult(
            settingsPath: settingsPath,
            backupPath: backupPath,
            installedEvents: touchedEvents.sorted()
        )
    }

    public static func isInstalled(
        settingsPath: String = defaultSettingsPath,
        events: [String] = defaultEvents
    ) throws -> Bool {
        let settings = try readSettings(at: settingsPath)
        guard case .object(let root) = settings else {
            throw ClaudeHookSettingsError.invalidSettingsRoot
        }
        guard case .object(let hooksObject) = root["hooks"] ?? .object([:]) else {
            throw ClaudeHookSettingsError.invalidHooksRoot
        }

        for event in events {
            guard let groups = hooksObject[event]?.arrayValue,
                  groups.contains(where: containsClawdPetHook) else {
                return false
            }
        }

        return true
    }

    private static func hookGroup(hookBinaryPath: String) -> JSONValue {
        .object([
            "hooks": .array([
                .object([
                    "type": .string("command"),
                    "command": .string("\(quotedShellPath(hookBinaryPath)) --source codex"),
                    "timeout": .number(5)
                ])
            ])
        ])
    }

    private static func containsClawdPetHook(_ group: JSONValue) -> Bool {
        guard let groupObject = group.objectValue,
              let hookValues = groupObject["hooks"]?.arrayValue else {
            return false
        }

        return hookValues.contains { hookValue in
            guard let hookObject = hookValue.objectValue,
                  case .string(let command)? = hookObject["command"] else {
                return false
            }
            return command.contains(clawdPetMarker)
        }
    }

    private static func readSettings(at path: String) throws -> JSONValue {
        guard FileManager.default.fileExists(atPath: path) else {
            return .object([:])
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        if data.isEmpty {
            return .object([:])
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func write(_ settings: JSONValue, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: [.atomic])
    }

    private static func backupIfNeeded(_ path: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupPath = "\(path).clawdpet-backup-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))"
        try FileManager.default.copyItem(atPath: path, toPath: backupPath)
        return backupPath
    }

    private static func quotedShellPath(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
