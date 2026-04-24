import AppKit
import ClawdPetCore
import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var appModel: AppModel
    @State private var expandedSource: String?
    @State private var expandedSessionID: String?

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
        let requiresScroll = section.sessions.count > 2

        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    expandedSource = expandedSource == section.source ? nil : section.source
                    if expandedSource != section.source {
                        expandedSessionID = nil
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(section.sourceLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(section.headline)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.72))
                        .lineLimit(1)
                    Image(systemName: expandedSource == section.source ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            if expandedSource == section.source {
                Group {
                    if requiresScroll {
                        ScrollView {
                            sessionList(section.sessions)
                        }
                        .frame(maxHeight: 168)
                    } else {
                        sessionList(section.sessions)
                    }
                }
                .padding(.top, 2)
            }
        }
        .onChange(of: appModel.sourceSections.map(\.source)) { sources in
            if let expandedSource, !sources.contains(expandedSource) {
                self.expandedSource = nil
            }
            let sessionIDs = appModel.sourceSections.flatMap(\.sessions).map(\.id)
            if let expandedSessionID, !sessionIDs.contains(expandedSessionID) {
                self.expandedSessionID = nil
            }
        }
    }

    @ViewBuilder
    private func sessionList(_ sessions: [AppModel.SessionDisplay]) -> some View {
        VStack(spacing: 6) {
            ForEach(sessions) { session in
                sessionRow(session)
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: AppModel.SessionDisplay) -> some View {
        let isExpanded = expandedSessionID == session.id

        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                expandedSessionID = isExpanded ? nil : session.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.taskTitle ?? session.workspaceName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(session.eventText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                if let latestUserLine = session.latestUserLine, !latestUserLine.isEmpty {
                    Text("你: \(latestUserLine)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Color.primary.opacity(0.72))
                }

                if isExpanded {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            detailRow(title: "Source", value: session.source)
                            detailRow(title: "CWD", value: session.workingDirectoryText)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            detailRow(title: "Action", value: session.eventText)
                            detailRow(title: "Session", value: session.shortSessionID)
                        }
                    }
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Color.black.opacity(isExpanded ? 0.09 : 0.05),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}
