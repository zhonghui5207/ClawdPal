import ClawdPalCore
import Darwin
import Foundation

func sourceArgument(from arguments: [String]) -> String {
    var iterator = Array(arguments.dropFirst()).makeIterator()
    while let argument = iterator.next() {
        if argument == "--source", let value = iterator.next() {
            return value
        }
        if argument.hasPrefix("--source=") {
            return String(argument.dropFirst("--source=".count))
        }
    }
    return "claude"
}

struct WatchArguments {
    var processID: pid_t
    var source: String
    var sessionID: String
    var workingDirectory: String?
}

struct ProcessSnapshot {
    var pid: pid_t
    var parentPID: pid_t
    var command: String
}

func watchArguments(from arguments: [String]) -> WatchArguments? {
    var processID: pid_t?
    var source = "claude"
    var sessionID: String?
    var workingDirectory: String?
    var iterator = Array(arguments.dropFirst()).makeIterator()

    while let argument = iterator.next() {
        switch argument {
        case "--watch-process":
            if let value = iterator.next(), let parsed = Int32(value) {
                processID = parsed
            }
        case "--source":
            source = iterator.next() ?? source
        case "--session-id":
            sessionID = iterator.next()
        case "--cwd":
            workingDirectory = iterator.next()
        default:
            if argument.hasPrefix("--watch-process="),
               let parsed = Int32(String(argument.dropFirst("--watch-process=".count))) {
                processID = parsed
            } else if argument.hasPrefix("--source=") {
                source = String(argument.dropFirst("--source=".count))
            } else if argument.hasPrefix("--session-id=") {
                sessionID = String(argument.dropFirst("--session-id=".count))
            } else if argument.hasPrefix("--cwd=") {
                workingDirectory = String(argument.dropFirst("--cwd=".count))
            }
        }
    }

    guard let processID, processID > 1, let sessionID, !sessionID.isEmpty else {
        return nil
    }
    return WatchArguments(
        processID: processID,
        source: source,
        sessionID: sessionID,
        workingDirectory: workingDirectory
    )
}

func isProcessAlive(_ pid: pid_t) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
}

func runWatcher(_ arguments: WatchArguments) {
    while isProcessAlive(arguments.processID) {
        sleep(1)
    }

    let event = AgentEvent(
        kind: .completed,
        hookEventName: "Exit",
        message: "Process exited",
        sessionID: arguments.sessionID,
        workingDirectory: arguments.workingDirectory
    )
    let envelopeSource = arguments.source == "codex" ? "codex" : "claude-code"
    try? BridgeClient().send(BridgeEnvelope(source: envelopeSource, event: event))
}

func processSnapshot(pid: pid_t) -> ProcessSnapshot? {
    let process = Process()
    let outputPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-p", "\(pid)", "-o", "pid=", "-o", "ppid=", "-o", "command="]
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
        return nil
    }

    guard let line = output.split(separator: "\n").first else {
        return nil
    }
    let fields = line
        .split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        .map(String.init)
    guard fields.count == 3,
          let resolvedPID = Int32(fields[0]),
          let parentPID = Int32(fields[1]) else {
        return nil
    }

    return ProcessSnapshot(
        pid: resolvedPID,
        parentPID: parentPID,
        command: fields[2]
    )
}

func watchedAgentProcessID(source: String) -> pid_t? {
    let source = source.lowercased()
    var currentPID = getppid()
    var visited: Set<pid_t> = []

    while currentPID > 1, !visited.contains(currentPID), let snapshot = processSnapshot(pid: currentPID) {
        visited.insert(currentPID)
        if source == "codex", commandLooksLikeCodex(snapshot.command) {
            return snapshot.pid
        }
        if source != "codex", commandLooksLikeClaude(snapshot.command) {
            return snapshot.pid
        }
        currentPID = snapshot.parentPID
    }

    return nil
}

func commandTokens(_ command: String) -> [String] {
    command
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)
}

func executableBasename(_ token: String) -> String {
    URL(fileURLWithPath: token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))).lastPathComponent.lowercased()
}

func commandLooksLikeCodex(_ command: String) -> Bool {
    let tokens = commandTokens(command)
    guard let executable = tokens.first.map(executableBasename) else {
        return false
    }
    if executable == "codex" {
        return true
    }
    if executable == "node" {
        return tokens.dropFirst().contains { executableBasename($0) == "codex" }
    }
    return false
}

func commandLooksLikeClaude(_ command: String) -> Bool {
    let tokens = commandTokens(command)
    guard let executable = tokens.first.map(executableBasename) else {
        return false
    }
    if executable == "claude" || executable == "ccs" {
        return true
    }
    if executable == "node" {
        return tokens.dropFirst().contains { token in
            let basename = executableBasename(token)
            return basename == "claude" || basename == "ccs"
        }
    }
    return false
}

func launchWatcher(source: String, event: AgentEvent) {
    guard let sessionID = event.sessionID, !sessionID.isEmpty,
          let processID = watchedAgentProcessID(source: source) else {
        return
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    var arguments = [
        "--watch-process", "\(processID)",
        "--source", source,
        "--session-id", sessionID
    ]
    if let workingDirectory = event.workingDirectory, !workingDirectory.isEmpty {
        arguments.append(contentsOf: ["--cwd", workingDirectory])
    }
    process.arguments = arguments
    process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
    process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
    process.standardError = FileHandle(forWritingAtPath: "/dev/null")
    try? process.run()
}

if let arguments = watchArguments(from: CommandLine.arguments) {
    runWatcher(arguments)
    exit(0)
}

let input = FileHandle.standardInput.readDataToEndOfFile()
let source = sourceArgument(from: CommandLine.arguments)

guard !input.isEmpty else {
    exit(0)
}

do {
    let event: AgentEvent
    let envelopeSource: String
    switch source {
    case "codex":
        event = try CodexHookDecoder.decodeEvent(from: input)
        envelopeSource = "codex"
    default:
        event = try ClaudeHookDecoder.decodeEvent(from: input)
        envelopeSource = "claude-code"
    }

    let envelope = BridgeEnvelope(source: envelopeSource, event: event)
    try BridgeClient().send(envelope)
    launchWatcher(source: source, event: event)
} catch {
    // Agent hooks should fail open. The agent must keep running even when ClawdPal is closed.
    fputs("ClawdPal hook warning: \(error)\n", stderr)
}
