import AppKit
import ClawdPalCore
import SwiftUI

private enum PetSpriteMotion {
    static let breathScale: CGFloat = 1.01
    static let restScale: CGFloat = 0.995
    static let pressedScale: CGFloat = 0.985
    static let floatOffset: CGFloat = 3
    static let pointerTilt: CGFloat = 2.8
    static let pointerX: CGFloat = 4.5
    static let pointerY: CGFloat = 2
    static let breathDuration: TimeInterval = 2.8
    static let floatDuration: TimeInterval = 4.2
    static let blinkRange: ClosedRange<Double> = 2.6...5.6
}

struct PetSpriteView: View {
    var mood: PetMood
    var pointerOffset: CGSize = .zero
    var isPressed = false
    var isAnimated = true
    var eventKind: AgentEventKind = .idle

    @State private var breathing = false
    @State private var floating = false
    @State private var blinkAmount: CGFloat = 0.0
    @State private var reactionX: CGFloat = 0.0
    @State private var reactionY: CGFloat = 0.0
    @State private var reactionTilt: CGFloat = 0.0

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
        .scaleEffect(spriteScale, anchor: .center)
        .rotationEffect(.degrees(Double(animatedPointerOffset.width * PetSpriteMotion.pointerTilt + reactionTilt)), anchor: .bottom)
        .offset(x: animatedPointerOffset.width * PetSpriteMotion.pointerX + reactionX, y: verticalOffset + reactionY)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(mood.displayName))
        .onAppear {
            guard isAnimated else { return }
            withAnimation(.easeInOut(duration: PetSpriteMotion.breathDuration).repeatForever(autoreverses: true)) {
                breathing = true
            }
            withAnimation(.easeInOut(duration: PetSpriteMotion.floatDuration).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
        .task {
            guard isAnimated else { return }
            while !Task.isCancelled {
                let delay = UInt64(Double.random(in: PetSpriteMotion.blinkRange) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { break }
                await blink()
            }
        }
        .task(id: eventKind) {
            guard isAnimated else { return }
            await react(to: eventKind)
        }
    }

    private var spriteScale: CGFloat {
        guard isAnimated else { return 1 }
        if isPressed { return PetSpriteMotion.pressedScale }
        return breathing ? PetSpriteMotion.breathScale : PetSpriteMotion.restScale
    }

    private var verticalOffset: CGFloat {
        guard isAnimated else { return 0 }
        let floatY = floating ? -PetSpriteMotion.floatOffset : PetSpriteMotion.floatOffset
        return floatY - animatedPointerOffset.height * PetSpriteMotion.pointerY
    }

    private var animatedPointerOffset: CGSize {
        isAnimated ? pointerOffset : .zero
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

    @MainActor
    private func react(to kind: AgentEventKind) async {
        switch kind {
        case .completed:
            withAnimation(.easeOut(duration: 0.10)) {
                reactionY = 3
            }
            try? await Task.sleep(nanoseconds: 95_000_000)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
                reactionY = 0
            }
        case .error, .permissionRequest:
            let frames: [(CGFloat, CGFloat)] = [(-4, -1.2), (3, 0.9), (-2, -0.5), (0, 0)]
            for (x, tilt) in frames {
                withAnimation(.easeInOut(duration: 0.06)) {
                    reactionX = x
                    reactionTilt = tilt
                }
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        default:
            withAnimation(.easeOut(duration: 0.12)) {
                reactionX = 0
                reactionY = 0
                reactionTilt = 0
            }
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
