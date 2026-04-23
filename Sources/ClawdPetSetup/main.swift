import ClawdPetCore
import Foundation

enum SetupCommand: String {
    case installClaude = "install-claude"
    case uninstallClaude = "uninstall-claude"
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
    let sibling = executablePath.deletingLastPathComponent().appendingPathComponent("ClawdPetHooks").path
    if FileManager.default.fileExists(atPath: sibling) {
        return sibling
    }

    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/ClawdPetHooks")
        .path
}

func printUsage() {
    print("""
    ClawdPetSetup

    Commands:
      install-claude [--settings ~/.claude/settings.json] [--hook /path/to/ClawdPetHooks]
      uninstall-claude [--settings ~/.claude/settings.json]
      print-hook-path

    Build first:
      swift build

    Then install:
      swift run ClawdPetSetup install-claude
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
        print("Installed ClawdPet Claude hooks")
        print("Settings: \(result.settingsPath)")
        if let backupPath = result.backupPath {
            print("Backup: \(backupPath)")
        }
        print("Hook binary: \(hookPath)")
        print("Events: \(result.installedEvents.joined(separator: ", "))")
    case .uninstallClaude:
        let result = try ClaudeHookSettings.uninstall(settingsPath: options.settingsPath)
        print("Removed ClawdPet Claude hooks")
        print("Settings: \(result.settingsPath)")
        if let backupPath = result.backupPath {
            print("Backup: \(backupPath)")
        }
        print("Events touched: \(result.installedEvents.joined(separator: ", "))")
    case .printHookPath:
        print(inferredHookPath())
    case .help:
        printUsage()
    }
} catch {
    fputs("ClawdPetSetup error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
