import AppKit
import ClawdPetCore
import SwiftUI

struct PetSpriteView: View {
    var mood: PetMood

    var body: some View {
        Group {
            if let image = ClawdPetImageStore.shared.image(for: mood) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange)
                    .overlay(Text(mood.displayName).font(.caption).foregroundStyle(.black))
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(Text(mood.displayName))
    }
}

final class ClawdPetImageStore {
    static let shared = ClawdPetImageStore()

    private var cache: [PetMood: NSImage] = [:]

    private init() {}

    func image(for mood: PetMood) -> NSImage? {
        if let cached = cache[mood] {
            return cached
        }

        guard let url = Bundle.module.url(
            forResource: resourceName(for: mood),
            withExtension: "png",
            subdirectory: "Resources/Pets"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }

        cache[mood] = image
        return image
    }

    private func resourceName(for mood: PetMood) -> String {
        switch mood {
        case .classic:
            return "classic_clawd"
        case .hoodie:
            return "hoodie_clawd"
        case .street:
            return "street_clawd"
        case .suit:
            return "suit_clawd"
        case .explorer:
            return "explorer_clawd"
        case .pajama:
            return "pajama_clawd"
        }
    }
}
