import AppKit
import ClawdPalCore
import SwiftUI

struct PetSpriteView: View {
    var mood: PetMood

    @State private var breathing = false
    @State private var floating = false
    @State private var squashX: CGFloat = 1.0
    @State private var squashY: CGFloat = 1.0

    var body: some View {
        Group {
            if let image = ClawdPalImageStore.shared.image(for: mood) {
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
        .scaleEffect(x: squashX, y: squashY, anchor: .center)
        .scaleEffect(breathing ? 1.02 : 0.98, anchor: .center)
        .offset(y: floating ? -0.8 : 0.8)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(mood.displayName))
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                breathing = true
            }
            withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
        .task {
            while !Task.isCancelled {
                let delay = UInt64(Double.random(in: 4.5...7.5) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { break }
                await perk()
            }
        }
    }

    @MainActor
    private func perk() async {
        withAnimation(.easeOut(duration: 0.09)) {
            squashX = 1.04
            squashY = 0.96
        }
        try? await Task.sleep(nanoseconds: 95_000_000)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            squashX = 1.0
            squashY = 1.0
        }
    }
}

final class ClawdPalImageStore {
    static let shared = ClawdPalImageStore()

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
