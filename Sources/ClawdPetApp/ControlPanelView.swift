import AppKit
import ClawdPetCore
import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var appModel: AppModel

    private let columns = [
        GridItem(.adaptive(minimum: 34, maximum: 42), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ClawdPet")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(appModel.mood.rawValue)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Quit ClawdPet")
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(PetMood.allCases, id: \.self) { mood in
                    Button {
                        appModel.setMood(mood)
                    } label: {
                        PetSpriteView(mood: mood)
                            .frame(width: 34, height: 30)
                            .padding(4)
                            .background(selectionBackground(for: mood), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(mood.displayName)
                }
            }

            Button {
                appModel.jumpBackToTerminal()
            } label: {
                Label("Jump Back", systemImage: "terminal")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Activate terminal")

            Text(appModel.bridgeStatus)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    private func selectionBackground(for mood: PetMood) -> Color {
        mood == appModel.mood ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.08)
    }
}
