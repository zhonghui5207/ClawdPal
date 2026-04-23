import AppKit
import ClawdPetCore
import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var appModel: AppModel

    private let columns = [
        GridItem(.fixed(42), spacing: 8),
        GridItem(.fixed(42), spacing: 8),
        GridItem(.fixed(42), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ClawdPet")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
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

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    detailRow(title: "Source", value: appModel.panelSourceText)
                    detailRow(title: "CWD", value: appModel.panelWorkingDirectoryText)
                }

                VStack(alignment: .leading, spacing: 6) {
                    detailRow(title: "Event", value: appModel.panelEventText)
                    detailRow(title: "Session", value: appModel.panelSessionText)
                }
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(PetMood.allCases, id: \.self) { mood in
                    Button {
                        appModel.setMood(mood)
                    } label: {
                        PetSpriteView(mood: mood)
                            .frame(width: 30, height: 28)
                            .padding(6)
                            .background(selectionBackground(for: mood), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(mood.displayName)
                }
            }
            .frame(width: 142, alignment: .leading)
            .padding(.top, 2)

            HStack(spacing: 6) {
                Button {
                    appModel.jumpBackToTerminal()
                } label: {
                    Label("Terminal", systemImage: "terminal")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Activate terminal")

                Button {
                    appModel.connectOrRepairHooks()
                } label: {
                    Label(appModel.hookPrimaryActionTitle, systemImage: appModel.hookPrimaryActionIcon)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(appModel.hookPrimaryActionHelp)
            }

            HStack {
                if !appModel.activeSessionSummary.isEmpty {
                    Text(appModel.activeSessionSummary)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(appModel.panelBridgeStatusText)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(appModel.panelBridgeStatusHelp)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 248)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
        }
    }

    private func selectionBackground(for mood: PetMood) -> Color {
        mood == appModel.mood ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.08)
    }
}
