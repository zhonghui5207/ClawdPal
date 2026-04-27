import Foundation
import ClawdPalCore

enum PresentationMode: String, CaseIterable, Identifiable {
    case normal
    case quiet
    case minimal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal:
            return "Normal"
        case .quiet:
            return "Quiet"
        case .minimal:
            return "Minimal"
        }
    }

    var allowsSpriteAnimation: Bool {
        self == .normal
    }

    func allowsBubble(for kind: AgentEventKind) -> Bool {
        switch self {
        case .normal:
            return true
        case .quiet:
            switch kind {
            case .completed, .permissionRequest, .error:
                return true
            case .idle, .thinking, .reading, .runningCommand, .editingCode, .unknown:
                return false
            }
        case .minimal:
            return false
        }
    }
}
