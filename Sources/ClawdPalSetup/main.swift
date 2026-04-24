import ClawdPalCore
import Foundation

enum SetupCommand: String {
    case installClaude = "install-claude"
    case uninstallClaude = "uninstall-claude"
    case installCodex = "install-codex"
    case uninstallCodex = "uninstall-codex"
    case installAll = "install-all"
    case uninstallAll = "uninstall-all"
    case printHookPath = "print-hook-path"
    case help = "help"
}

struct SetupOptions {
    var command: SetupCommand
    var settingsPath: String = ClaudeHookSettings.defaultSettingsPath
    var hookPath: String?
}

func parseOptions(_ arguments: [String]) -> SetupOptions {
    var options = SetupOptions(command: arguments.dropFirst().first.flatMap(SetupCommand.init(rawValue:)) ?? .help)
    var iterator = Array(arguments.dropFirst(2)).makeIterator()

    while let argument = iterator.next() {
        switch argument {
        case "--settings":
            if let value = iterator.next() {
                options.settingsPath = expandedPath(value)
            }
        case "--hook":
            if let value = iterator.next() {
                options.hookPath = expandedPath(value)
            }
        default:
            continue
        }
    }

    return options
}

func expandedPath(_ path: String) -> String {
    if path == "~" {
        return FileManager.default.homeDirectoryForCurrentUser.path
    }
    if path.hasPrefix("~/") {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(String(path.dropFirst(2)))
            .path
    }
    return path
}

func inferredHookPath() -> String {
    let executablePath = URL(fileURLWithPath: CommandLine.arguments[0])
    let sibling = executablePath.deletingLastPathComponent().appendingPathComponent("ClawdPalHooks").path
    if FileManager.default.fileExists(atPath: sibling) {
        return sibling
    }

    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/ClawdPalHooks")
        .path
}

func printUsage() {
    print("""
    ClawdPal Setup

    Commands:
      install-claude [--settings ~/.claude/settings.json] [--hook /path/to/ClawdPalHooks]
      uninstall-claude [--settings ~/.claude/settings.json]
      install-codex [--settings ~/.codex/hooks.json] [--hook /path/to/ClawdPalHooks]
      uninstall-codex [--settings ~/.codex/hooks.json]
      install-all [--hook /path/to/ClawdPalHooks]
      uninstall-all
      print-hook-path

    Build first:
      swift build

    Then install:
      swift run ClawdPalSetup install-all
    """)
}

let options = parseOptions(CommandLine.arguments)

do {
    switch options.command {
    case .installClaude:
        let hookPath = options.hookPath ?? inferredHookPath()
        let result = try ClaudeHookSettings.install(
            settingsPath: options.settingsPath,
            hookBinaryPath: hookPath
        )
        print("Installed ClawdPal Claude hooks")
        print("Settings: \(result.settingsPath)")
        if let backupPath = result.backupPath {
            print("Backup: \(backupPath)")
        }
        print("Hook binary: \(hookPath)")
        print("Events: \(result.installedEvents.joined(separator: ", "))")
    case .uninstallClaude:
        let result = try ClaudeHookSettings.uninstall(settingsPath: options.settingsPath)
        print("Removed ClawdPal Claude hooks")
        print("Settings: \(result.settingsPath)")
        if let backupPath = result.backupPath {
            print("Backup: \(backupPath)")
        }
        print("Events touched: \(result.installedEvents.joined(separator: ", "))")
    case .installCodex:
        let hookPath = options.hookPath ?? inferredHookPath()
        let settingsPath = options.settingsPath == ClaudeHookSettings.defaultSettingsPath
            ? CodexHookSettings.defaultSettingsPath
            : options.settingsPath
        let result = try CodexHookSettings.install(
            settingsPath: settingsPath,
            hookBinaryPath: hookPath
        )
        print("Installed ClawdPal Codex hooks")
        print("Settings: \(result.settingsPath)")
        if let backupPath = result.backupPath {
            print("Backup: \(backupPath)")
        }
        print("Hook binary: \(hookPath)")
        print("Events: \(result.installedEvents.joined(separator: ", "))")
    case .uninstallCodex:
        let settingsPath = options.settingsPath == ClaudeHookSettings.defaultSettingsPath
            ? CodexHookSettings.defaultSettingsPath
            : options.settingsPath
        let result = try CodexHookSettings.uninstall(settingsPath: settingsPath)
        print("Removed ClawdPal Codex hooks")
        print("Settings: \(result.settingsPath)")
        if let backupPath = result.backupPath {
            print("Backup: \(backupPath)")
        }
        print("Events touched: \(result.installedEvents.joined(separator: ", "))")
    case .installAll:
        let hookPath = options.hookPath ?? inferredHookPath()
        let claude = try ClaudeHookSettings.install(hookBinaryPath: hookPath)
        let codex = try CodexHookSettings.install(hookBinaryPath: hookPath)
        print("Installed ClawdPal hooks")
        print("Claude settings: \(claude.settingsPath)")
        if let backupPath = claude.backupPath {
            print("Claude backup: \(backupPath)")
        }
        print("Codex settings: \(codex.settingsPath)")
        if let backupPath = codex.backupPath {
            print("Codex backup: \(backupPath)")
        }
        print("Hook binary: \(hookPath)")
    case .uninstallAll:
        let claude = try ClaudeHookSettings.uninstall()
        let codex = try CodexHookSettings.uninstall()
        print("Removed ClawdPal hooks")
        print("Claude settings: \(claude.settingsPath)")
        if let backupPath = claude.backupPath {
            print("Claude backup: \(backupPath)")
        }
        print("Codex settings: \(codex.settingsPath)")
        if let backupPath = codex.backupPath {
            print("Codex backup: \(backupPath)")
        }
    case .printHookPath:
        print(inferredHookPath())
    case .help:
        printUsage()
    }
} catch {
    fputs("ClawdPal setup error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
