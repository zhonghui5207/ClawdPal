import AppKit
import ClawdPetCore
import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var appModel: AppModel
    @State private var expandedSource: String?

    private let columns = [
        GridItem(.fixed(52), spacing: 8),
        GridItem(.fixed(52), spacing: 8),
        GridItem(.fixed(52), spacing: 8)
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

            if let title = appModel.panelTitleText {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            if let userLine = appModel.panelLatestUserLineText {
                Text("你: \(userLine)")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    detailRow(title: "Source", value: appModel.panelSourceText)
                    detailRow(title: "CWD", value: appModel.panelWorkingDirectoryText)
                }

                VStack(alignment: .leading, spacing: 6) {
                    detailRow(title: "Action", value: appModel.panelEventText)
                    detailRow(title: "Session", value: appModel.panelSessionText)
                }
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(.secondary)

            if !appModel.sourceSections.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appModel.sourceSections) { section in
                        sourceSection(section)
                    }
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(PetMood.allCases, id: \.self) { mood in
                    Button {
                        appModel.setMood(mood)
                    } label: {
                        PetSpriteView(mood: mood)
                            .frame(width: 42, height: 40)
                            .padding(5)
                            .background(selectionBackground(for: mood), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(mood.displayName)
                }
            }
            .frame(width: 172, alignment: .leading)
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

    @ViewBuilder
    private func sourceSection(_ section: AppModel.SourceSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    expandedSource = expandedSource == section.source ? nil : section.source
                }
            } label: {
                HStack(spacing: 8) {
                    Text(section.sourceLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(section.headline)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: expandedSource == section.source ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            if expandedSource == section.source {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(section.sessions) { session in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(session.taskTitle ?? session.workspaceName)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(session.shortSessionID)
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                }

                                if let latestUserLine = session.latestUserLine, !latestUserLine.isEmpty {
                                    Text("你: \(latestUserLine)")
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 8) {
                                    Text(session.eventText)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 0)
                                    Text(session.workspaceName)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 104)
            }
        }
        .onChange(of: appModel.sourceSections.map(\.source)) { sources in
            if let expandedSource, !sources.contains(expandedSource) {
                self.expandedSource = nil
            }
        }
    }
}
