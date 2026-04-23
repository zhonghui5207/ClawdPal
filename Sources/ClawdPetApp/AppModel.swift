import ClawdPetCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var mood: PetMood = .classic
    @Published private(set) var bubbleText: String = "Idle"
    @Published private(set) var lastEvent: AgentEvent?
    @Published private(set) var bridgeStatus: String = "Starting..."

    private let bridgeServer = BridgeServer()
    private let terminalJumpService = TerminalJumpService()
    private var completionTimer: Timer?

    func start() {
        do {
            try bridgeServer.start { [weak self] envelope in
                Task { @MainActor in
                    self?.apply(envelope)
                }
            }
            bridgeStatus = "Listening on \(BridgePath.defaultSocketPath)"
        } catch {
            bridgeStatus = "Bridge error: \(error)"
            bubbleText = "Bridge offline"
        }
    }

    func stop() {
        completionTimer?.invalidate()
        bridgeServer.stop()
    }

    func setMood(_ mood: PetMood) {
        self.mood = mood
        self.bubbleText = mood.displayName
    }

    func jumpBackToTerminal() {
        bubbleText = terminalJumpService.activateTerminal()
    }

    func resetWindowPosition() {
        NotificationCenter.default.post(name: .clawdPetResetWindowPosition, object: nil)
    }

    private func apply(_ envelope: BridgeEnvelope) {
        completionTimer?.invalidate()
        lastEvent = envelope.event

        let presentation = PetMoodMapper.presentation(for: envelope.event)
        mood = presentation.mood
        bubbleText = presentation.bubbleText

        if envelope.event.kind == .completed {
            completionTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.mood = .classic
                    self?.bubbleText = "Idle"
                }
            }
        }
    }
}

extension Notification.Name {
    static let clawdPetResetWindowPosition = Notification.Name("clawdPetResetWindowPosition")
    static let clawdPetDragEnded = Notification.Name("clawdPetDragEnded")
}
