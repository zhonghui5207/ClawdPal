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
            return "Classic Clawd"
        case .hoodie:
            return "Hoodie Clawd"
        case .street:
            return "Street Clawd"
        case .suit:
            return "Suit Clawd"
        case .explorer:
            return "Explorer Clawd"
        case .pajama:
            return "Pajama Clawd"
        }
    }
}
