import AppKit
import ClawdPalCore
import SwiftUI

struct PetSpriteView: View {
    var mood: PetMood
    var pointerOffset: CGSize = .zero

    @State private var breathing = false
    @State private var floating = false
    @State private var blinkAmount: CGFloat = 0.0

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
        .overlay(blinkOverlay)
        .scaleEffect(breathing ? 1.01 : 0.995, anchor: .center)
        .rotationEffect(.degrees(Double(pointerOffset.width * 2.8)), anchor: .bottom)
        .offset(x: pointerOffset.width * 4.5, y: (floating ? -3.0 : 3.0) - pointerOffset.height * 2.0)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(mood.displayName))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                breathing = true
            }
            withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
        .task {
            while !Task.isCancelled {
                let delay = UInt64(Double.random(in: 2.6...5.6) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { break }
                await blink()
            }
        }
    }

    private var blinkOverlay: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let originX = (geometry.size.width - side) / 2
            let originY = (geometry.size.height - side) / 2

            ZStack {
                eyelid(in: side, originX: originX, originY: originY, centerX: 0.363)
                eyelid(in: side, originX: originX, originY: originY, centerX: 0.637)
            }
            .opacity(blinkAmount)
        }
        .allowsHitTesting(false)
    }

    private func eyelid(in side: CGFloat, originX: CGFloat, originY: CGFloat, centerX: CGFloat) -> some View {
        let coverWidth = side * 0.058
        let coverHeight = side * 0.12
        let lineWidth = side * 0.038
        let lineHeight = max(side * 0.007, 1.5)

        return ZStack {
            RoundedRectangle(cornerRadius: side * 0.006)
                .fill(Color(red: 0.92, green: 0.49, blue: 0.31))
                .frame(width: coverWidth, height: coverHeight)

            Capsule()
                .fill(Color.black.opacity(0.86))
                .frame(width: lineWidth, height: lineHeight)
        }
        .position(x: originX + side * centerX, y: originY + side * 0.333)
    }

    @MainActor
    private func blink() async {
        withAnimation(.easeOut(duration: 0.055)) {
            blinkAmount = 1.0
        }
        try? await Task.sleep(nanoseconds: 85_000_000)
        withAnimation(.easeIn(duration: 0.08)) {
            blinkAmount = 0.0
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
