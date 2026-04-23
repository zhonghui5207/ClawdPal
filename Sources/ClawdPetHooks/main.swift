import ClawdPetCore
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()

guard !input.isEmpty else {
    exit(0)
}

do {
    let event = try ClaudeHookDecoder.decodeEvent(from: input)
    let envelope = BridgeEnvelope(source: "claude-code", event: event)
    try BridgeClient().send(envelope)
} catch {
    // Claude Code hooks should fail open. The agent must keep running even when ClawdPet is closed.
    fputs("ClawdPetHooks warning: \(error)\n", stderr)
}
