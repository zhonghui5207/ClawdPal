import Foundation

public enum PetMood: String, CaseIterable, Codable, Equatable, Sendable {
    case classic
    case hoodie
    case street
    case suit
    case explorer
    case pajama

    public var displayName: String {
        switch self {
        case .classic:
            return "Classic"
        case .hoodie:
            return "Hoodie"
        case .street:
            return "Street"
        case .suit:
            return "Suit"
        case .explorer:
            return "Explorer"
        case .pajama:
            return "Pajama"
        }
    }
}
