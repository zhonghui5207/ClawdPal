import ClawdPalCore
import SwiftUI

struct StatusBubbleView: View {
    var text: String
    var kind: AgentEventKind = .idle

    @State private var displayedText = ""
    @State private var popScale: CGFloat = 1.0
    @State private var doneLift: CGFloat = 0.0
    @State private var shakeX: CGFloat = 0.0

    var body: some View {
        let style = BubbleStyle(kind: kind)

        VStack(spacing: -1) {
            HStack(spacing: 7) {
                Image(systemName: style.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(style.accent)

                Text(displayedText.isEmpty ? text : displayedText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(style.background.opacity(style.opacity), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(style.accent.opacity(0.36), lineWidth: 1)
            )

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(style.background.opacity(style.opacity))
                .frame(width: 13, height: 13)
                .rotationEffect(.degrees(45))
                .offset(x: 2, y: -6)
        }
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
            .scaleEffect(popScale, anchor: .bottom)
            .offset(x: shakeX, y: doneLift)
            .onAppear {
                displayedText = text
            }
            .task(id: "\(kind.rawValue)-\(text)") {
                await animateMessage(text)
            }
    }

    @MainActor
    private func animateMessage(_ message: String) async {
        displayedText = ""

        withAnimation(.spring(response: 0.24, dampingFraction: 0.58)) {
            popScale = 1.18
        }
        try? await Task.sleep(nanoseconds: 130_000_000)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            popScale = 1.0
        }

        if kind == .error || kind == .permissionRequest {
            await shake()
        }

        if kind == .completed || isCompletionMessage(message) {
            withAnimation(.easeOut(duration: 0.1)) {
                doneLift = -10
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.46)) {
                doneLift = 0
            }
        }

        let characters = Array(message)
        let limit = min(characters.count, 80)
        for index in 0..<limit {
            if Task.isCancelled { return }
            displayedText = String(characters[0...index])
            let pause = characters[index].isWhitespace ? 24_000_000 : 42_000_000
            try? await Task.sleep(nanoseconds: UInt64(pause))
        }

        if characters.count > limit {
            displayedText += "..."
        }
    }

    private func isCompletionMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("done")
            || normalized.contains("complete")
            || normalized.contains("finished")
    }

    @MainActor
    private func shake() async {
        for offset in [-7.0, 6.0, -4.0, 3.0, 0.0] {
            withAnimation(.easeInOut(duration: 0.055)) {
                shakeX = offset
            }
            try? await Task.sleep(nanoseconds: 55_000_000)
        }
    }
}

private struct BubbleStyle {
    var symbol: String
    var background: Color
    var accent: Color
    var opacity: Double

    init(kind: AgentEventKind) {
        switch kind {
        case .thinking:
            symbol = "ellipsis"
            background = Color(red: 0.15, green: 0.15, blue: 0.22)
            accent = Color(red: 0.62, green: 0.72, blue: 1.0)
            opacity = 0.82
        case .reading:
            symbol = "magnifyingglass"
            background = Color(red: 0.06, green: 0.20, blue: 0.20)
            accent = Color(red: 0.37, green: 0.92, blue: 0.86)
            opacity = 0.82
        case .runningCommand:
            symbol = "terminal"
            background = Color(red: 0.20, green: 0.16, blue: 0.08)
            accent = Color(red: 1.0, green: 0.74, blue: 0.28)
            opacity = 0.84
        case .editingCode:
            symbol = "curlybraces"
            background = Color(red: 0.08, green: 0.18, blue: 0.11)
            accent = Color(red: 0.48, green: 0.95, blue: 0.55)
            opacity = 0.83
        case .completed:
            symbol = "checkmark"
            background = Color(red: 0.08, green: 0.18, blue: 0.13)
            accent = Color(red: 0.56, green: 1.0, blue: 0.60)
            opacity = 0.86
        case .permissionRequest:
            symbol = "exclamationmark.triangle"
            background = Color(red: 0.23, green: 0.14, blue: 0.06)
            accent = Color(red: 1.0, green: 0.58, blue: 0.22)
            opacity = 0.86
        case .error:
            symbol = "xmark"
            background = Color(red: 0.24, green: 0.07, blue: 0.07)
            accent = Color(red: 1.0, green: 0.36, blue: 0.32)
            opacity = 0.88
        case .idle, .unknown:
            symbol = "sparkle"
            background = .black
            accent = .white
            opacity = 0.74
        }
    }
}
