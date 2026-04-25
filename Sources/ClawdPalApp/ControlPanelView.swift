import AppKit
import ClawdPalCore
import SwiftUI

private enum ControlPanelPalette {
    static let primaryText = Color.black.opacity(0.90)
    static let secondaryText = Color.black.opacity(0.74)
    static let mutedText = Color.black.opacity(0.66)
    static let controlBackground = Color.black.opacity(0.11)
    static let controlBackgroundStrong = Color.black.opacity(0.15)
}

private struct StatusStyle {
    var label: String
    var textColor: Color
    var backgroundColor: Color
}

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
                Text("ClawdPal")
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
                .help("Quit ClawdPal")
            }

            if !appModel.sourceSections.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appModel.sourceSections) { section in
                        sourceSection(section)
                    }
                }
            }

            if appModel.isHookManagerOpen {
                HookManagerView(appModel: appModel)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(PetMood.allCases, id: \.self) { mood in
                    Button {
                        appModel.setMood(mood)
                    } label: {
                        PetSpriteView(mood: mood, isAnimated: false)
                            .frame(width: 42, height: 40)
                            .padding(5)
                            .background(selectionBackground(for: mood), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(mood.displayName)
                }
            }
            .frame(width: 172, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)

            HStack {
                if !appModel.activeSessionSummary.isEmpty {
                    Text(appModel.activeSessionSummary)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(ControlPanelPalette.mutedText)
                        .lineLimit(1)
                }
                Spacer()
                Text(appModel.panelBridgeStatusText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ControlPanelPalette.mutedText)
                    .lineLimit(1)
                    .help(appModel.panelBridgeStatusHelp)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 220)
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
                .foregroundStyle(ControlPanelPalette.primaryText)
        }
    }

    private func selectionBackground(for mood: PetMood) -> Color {
        mood == appModel.mood ? Color.accentColor.opacity(0.22) : ControlPanelPalette.controlBackground
    }

    @ViewBuilder
    private func sourceSection(_ section: AppModel.SourceSection) -> some View {
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
                            .frame(minWidth: 44, alignment: .leading)

                        if let leadingSession = section.sessions.first {
                            statusChip(for: leadingSession)
                            Text(leadingSession.taskTitle ?? leadingSession.workspaceName)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(ControlPanelPalette.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text(section.headline)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(ControlPanelPalette.secondaryText)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: expandedSource == section.source ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ControlPanelPalette.secondaryText)
                            .frame(width: 12)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                .background(ControlPanelPalette.controlBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            if expandedSource == section.source {
                sessionList(section.sessions)
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

        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    expandedSessionID = isExpanded ? nil : session.id
                }
            } label: {
                sessionCard(session, isExpanded: isExpanded)
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(spacing: 6) {
                    Button {
                        appModel.jumpToSession(session)
                    } label: {
                        Label("Jump", systemImage: "terminal")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .foregroundStyle(ControlPanelPalette.primaryText)
                            .background(ControlPanelPalette.controlBackgroundStrong, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Open terminal at this session's working directory")

                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            expandedSessionID = nil
                            appModel.archiveSession(session)
                        }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .foregroundStyle(ControlPanelPalette.primaryText)
                            .background(ControlPanelPalette.controlBackgroundStrong, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Hide this session until it becomes active again")
                }
            }
        }
    }

    @ViewBuilder
    private func sessionCard(_ session: AppModel.SessionDisplay, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    statusChip(for: session)

                    Text(session.taskTitle ?? session.workspaceName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ControlPanelPalette.mutedText)
                }

                if let latestUserLine = session.latestUserLine, !latestUserLine.isEmpty {
                    Text("你: \(latestUserLine)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(ControlPanelPalette.secondaryText)
                }
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
            .foregroundStyle(ControlPanelPalette.secondaryText)
                .padding(.top, 2)

                if !session.subagents.isEmpty {
                    subagentList(session.subagents)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isExpanded ? ControlPanelPalette.controlBackgroundStrong : ControlPanelPalette.controlBackground,
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func subagentList(_ subagents: [AppModel.SubagentDisplay]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 8, weight: .bold))
                Text("Subagents (\(subagents.count))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(ControlPanelPalette.secondaryText)

            ForEach(subagents) { subagent in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.45, blue: 0.90))
                            .frame(width: 6, height: 6)

                        Text("\(subagent.name) (\(subagent.taskTitle))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ControlPanelPalette.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 0)

                        Text(subagent.durationText)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(ControlPanelPalette.mutedText)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Text("└ \(subagent.actionText)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(ControlPanelPalette.mutedText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 12)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func statusChip(for session: AppModel.SessionDisplay) -> some View {
        let style = statusStyle(for: session)

        Text(style.label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(style.textColor)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(style.backgroundColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize(horizontal: true, vertical: false)
    }

    private func statusStyle(for session: AppModel.SessionDisplay) -> StatusStyle {
        if session.hasActiveSubagents {
            return StatusStyle(label: "Working", textColor: Color(red: 0.02, green: 0.13, blue: 0.34), backgroundColor: Color(red: 0.66, green: 0.78, blue: 0.98))
        }

        if !session.isActive {
            if session.kind == .completed {
                return StatusStyle(label: "Waiting", textColor: Color.black.opacity(0.88), backgroundColor: Color(red: 0.78, green: 0.77, blue: 0.68))
            }
            return StatusStyle(label: "Idle", textColor: Color.black.opacity(0.82), backgroundColor: Color(red: 0.74, green: 0.76, blue: 0.70))
        }

        switch session.kind {
        case .editingCode:
            return StatusStyle(label: "Editing", textColor: Color(red: 0.02, green: 0.13, blue: 0.34), backgroundColor: Color(red: 0.66, green: 0.78, blue: 0.98))
        case .runningCommand:
            return StatusStyle(label: "Command", textColor: Color(red: 0.02, green: 0.13, blue: 0.34), backgroundColor: Color(red: 0.66, green: 0.78, blue: 0.98))
        case .reading:
            return StatusStyle(label: "Reading", textColor: Color(red: 0.01, green: 0.23, blue: 0.25), backgroundColor: Color(red: 0.61, green: 0.88, blue: 0.86))
        case .thinking:
            return StatusStyle(label: "Thinking", textColor: Color(red: 0.17, green: 0.10, blue: 0.37), backgroundColor: Color(red: 0.77, green: 0.70, blue: 0.94))
        case .permissionRequest:
            return StatusStyle(label: "Permission", textColor: Color(red: 0.38, green: 0.18, blue: 0.00), backgroundColor: Color(red: 0.96, green: 0.70, blue: 0.40))
        case .error:
            return StatusStyle(label: "Error", textColor: Color(red: 0.46, green: 0.02, blue: 0.02), backgroundColor: Color(red: 0.96, green: 0.62, blue: 0.58))
        case .completed:
            return StatusStyle(label: "Done", textColor: Color(red: 0.03, green: 0.28, blue: 0.10), backgroundColor: Color(red: 0.66, green: 0.86, blue: 0.62))
        case .idle, .unknown:
            return StatusStyle(label: "Idle", textColor: Color.black.opacity(0.82), backgroundColor: Color(red: 0.74, green: 0.76, blue: 0.70))
        }
    }
}

private struct HookManagerView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("Hooks")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    appModel.hideHookManager()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Close hook manager")
            }

            VStack(spacing: 5) {
                ForEach(appModel.hookTargets) { target in
                    hookTargetRow(target)
                }
            }

            accessibilityRow()
        }
        .onAppear {
            appModel.refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appModel.refreshAccessibilityStatus()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(ControlPanelPalette.controlBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func accessibilityRow() -> some View {
        HStack(spacing: 8) {
            Image(systemName: appModel.isAccessibilityTrusted ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16)
                .foregroundStyle(appModel.isAccessibilityTrusted ? Color(red: 0.03, green: 0.35, blue: 0.12) : Color(red: 0.58, green: 0.04, blue: 0.04))

            VStack(alignment: .leading, spacing: 0) {
                Text("Terminal Access")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                Text(appModel.isAccessibilityTrusted ? "Ready" : "Needs access")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(appModel.isAccessibilityTrusted ? ControlPanelPalette.mutedText : Color(red: 0.58, green: 0.04, blue: 0.04))
                    .lineLimit(1)
                    .help("Allows ClawdPal to jump back to the matching terminal window")
            }

            Spacer()

            if appModel.isAccessibilityTrusted {
                EmptyView()
            } else {
                Button {
                    appModel.openAccessibilitySettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 22)
                        .foregroundStyle(ControlPanelPalette.primaryText)
                        .background(ControlPanelPalette.controlBackgroundStrong, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open Accessibility settings")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    @ViewBuilder
    private func hookTargetRow(_ target: AppModel.HookTargetDisplay) -> some View {
        HStack(spacing: 7) {
            Image(systemName: target.isConnected ? "checkmark.circle" : "link.badge.plus")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16)
                .foregroundStyle(target.needsRepair ? Color(red: 0.58, green: 0.04, blue: 0.04) : ControlPanelPalette.mutedText)

            VStack(alignment: .leading, spacing: 0) {
                Text(target.name)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(target.stateText)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(target.needsRepair ? Color(red: 0.58, green: 0.04, blue: 0.04) : ControlPanelPalette.mutedText)
                    .lineLimit(1)
                    .help(target.helpText)
            }

            Spacer(minLength: 0)

            Button {
                appModel.runPrimaryHookAction(for: target.id)
            } label: {
                Image(systemName: target.primaryActionIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 22)
                    .foregroundStyle(ControlPanelPalette.primaryText)
                    .background(ControlPanelPalette.controlBackgroundStrong, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("\(target.primaryActionTitle) \(target.name)")

            if target.isConnected {
                Button {
                    appModel.disconnectHook(target.id)
                } label: {
                    Image(systemName: "link.badge.minus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 22)
                        .foregroundStyle(ControlPanelPalette.primaryText)
                        .background(ControlPanelPalette.controlBackgroundStrong, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Disconnect \(target.name)")
            } else {
                Color.clear
                    .frame(width: 24, height: 22)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
