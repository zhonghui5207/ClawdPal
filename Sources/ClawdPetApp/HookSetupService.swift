import ClawdPetCore
import Foundation

struct HookSetupService {
    enum Action: String {
        case installClaude = "install-claude"
        case uninstallClaude = "uninstall-claude"
        case installCodex = "install-codex"
        case uninstallCodex = "uninstall-codex"
        case installAll = "install-all"
        case uninstallAll = "uninstall-all"
    }

    enum ConnectionState: Equatable {
        case connected
        case disconnected
        case broken(String)
    }

    struct Status: Equatable {
        var claude: ConnectionState
        var codex: ConnectionState

        static let disconnected = Status(claude: .disconnected, codex: .disconnected)

        var isFullyConnected: Bool {
            claude == .connected && codex == .connected
        }

        var needsRepair: Bool {
            switch (claude, codex) {
            case (.broken, _), (_, .broken):
                return true
            default:
                return false
            }
        }
    }

    func run(_ action: Action) throws -> String {
        let setupPath = try setupExecutablePath()
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: setupPath)
        process.arguments = [action.rawValue]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw SetupError.failed(errorOutput.isEmpty ? output : errorOutput)
        }

        return firstUsefulLine(from: output) ?? "Hooks updated"
    }

    func status() -> Status {
        Status(
            claude: connectionState { try ClaudeHookSettings.isInstalled() },
            codex: connectionState { try CodexHookSettings.isInstalled() }
        )
    }

    private func setupExecutablePath() throws -> String {
        let currentExecutable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let sibling = currentExecutable.deletingLastPathComponent().appendingPathComponent("ClawdPetSetup").path
        if FileManager.default.isExecutableFile(atPath: sibling) {
            return sibling
        }

        let debugPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/ClawdPetSetup")
            .path
        if FileManager.default.isExecutableFile(atPath: debugPath) {
            return debugPath
        }

        throw SetupError.missingExecutable
    }

    private func firstUsefulLine(from output: String) -> String? {
        output
            .split(separator: "\n")
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func connectionState(_ check: () throws -> Bool) -> ConnectionState {
        do {
            return try check() ? .connected : .disconnected
        } catch {
            return .broken(error.localizedDescription)
        }
    }
}

enum SetupError: Error, LocalizedError {
    case missingExecutable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "ClawdPal setup executable was not found."
        case .failed(let output):
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
