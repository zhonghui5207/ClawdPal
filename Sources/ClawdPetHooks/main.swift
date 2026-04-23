import ClawdPetCore
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
} catch {
    // Agent hooks should fail open. The agent must keep running even when ClawdPet is closed.
    fputs("ClawdPetHooks warning: \(error)\n", stderr)
}
