import Foundation

public struct PetPresentation: Equatable, Sendable {
    public var mood: PetMood
    public var bubbleText: String

    public init(mood: PetMood, bubbleText: String) {
        self.mood = mood
        self.bubbleText = bubbleText
    }
}

public enum PetMoodMapper {
    public static func presentation(for event: AgentEvent) -> PetPresentation {
        switch event.kind {
        case .idle:
            return PetPresentation(mood: .classic, bubbleText: "Idle")
        case .thinking:
            return PetPresentation(mood: .hoodie, bubbleText: event.message ?? "Thinking...")
        case .reading:
            return PetPresentation(mood: .explorer, bubbleText: toolText(event, fallback: "Reading project..."))
        case .runningCommand:
            return PetPresentation(mood: .street, bubbleText: toolText(event, fallback: "Running command..."))
        case .editingCode:
            return PetPresentation(mood: .suit, bubbleText: toolText(event, fallback: "Editing code..."))
        case .permissionRequest:
            return PetPresentation(mood: .hoodie, bubbleText: event.message ?? "Permission requested")
        case .error:
            return PetPresentation(mood: .street, bubbleText: event.message ?? "Agent error")
        case .completed:
            return PetPresentation(mood: .pajama, bubbleText: event.message ?? "Done.")
        case .unknown:
            return PetPresentation(mood: .classic, bubbleText: event.message ?? "Watching session")
        }
    }

    private static func toolText(_ event: AgentEvent, fallback: String) -> String {
        if let message = event.message, !message.isEmpty {
            return message
        }

        guard let toolName = event.toolName, !toolName.isEmpty else {
            return fallback
        }

        return "\(fallback.replacingOccurrences(of: "...", with: "")): \(toolName)"
    }
}
