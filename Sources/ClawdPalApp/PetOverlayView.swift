import ClawdPalCore
import AppKit
import SwiftUI

struct PetOverlayView: View {
    private struct PanelHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private enum Layout {
        static let width: CGFloat = 292
        static let compactHeight: CGFloat = 260
        static let fallbackExpandedHeight: CGFloat = 420
        static let spriteHeight: CGFloat = 150
        static let stackSpacing: CGFloat = 4
        static let verticalPadding: CGFloat = 8
        static let panelFadeDuration: CGFloat = 0.12
    }

    @ObservedObject var appModel: AppModel
    @State private var isPanelOpen = false
    @State private var window: NSWindow?
    @State private var measuredPanelHeight: CGFloat = 0
    @State private var pointerOffset: CGSize = .zero
    @State private var isPetPressed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: Layout.stackSpacing) {
                if isPanelOpen {
                    ControlPanelView(appModel: appModel)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(key: PanelHeightKey.self, value: geometry.size.height)
                            }
                        )
                        .transition(.opacity)
                }

                if !isPanelOpen {
                    StatusBubbleView(text: appModel.bubbleText, kind: appModel.focusedSession?.kind ?? appModel.lastEvent?.kind ?? .idle)
                        .frame(maxWidth: 260)
                }

                PetSpriteView(mood: appModel.mood, pointerOffset: pointerOffset, isPressed: isPetPressed)
                    .frame(width: 210, height: 150)
                    .contentShape(Rectangle())
                    .overlay(
                        PetInteractionView {
                            withAnimation(.easeOut(duration: Layout.panelFadeDuration)) {
                                isPanelOpen.toggle()
                            }
                        } onPointerMove: { offset in
                            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.72)) {
                                pointerOffset = offset
                            }
                        } onPointerExit: {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.76)) {
                                pointerOffset = .zero
                            }
                        } onPressChanged: { isPressed in
                            withAnimation(.spring(response: 0.18, dampingFraction: 0.70)) {
                                isPetPressed = isPressed
                            }
                        }
                    )
                    .help("Open ClawdPal panel")
            }
            .padding(.vertical, Layout.verticalPadding)
            .padding(.horizontal, 16)
        }
        .frame(
            width: Layout.width,
            height: currentHeight,
            alignment: .bottom
        )
        .background(Color.clear)
        .background(
            WindowAccessor { resolvedWindow in
                window = resolvedWindow
            }
            .frame(width: 0, height: 0)
        )
        .onChange(of: isPanelOpen) { isOpen in
            NotificationCenter.default.post(
                name: .clawdPalSetPanelOpen,
                object: nil,
                userInfo: ["isOpen": isOpen, "preferredHeight": currentHeight]
            )
        }
        .onPreferenceChange(PanelHeightKey.self) { newHeight in
            guard newHeight > 0 else { return }
            measuredPanelHeight = newHeight
            guard isPanelOpen else { return }
            NotificationCenter.default.post(
                name: .clawdPalSetPanelOpen,
                object: nil,
                userInfo: ["isOpen": true, "preferredHeight": currentHeight]
            )
        }
        .contextMenu {
            Button("Jump Back") {
                appModel.jumpBackToTerminal()
            }
            Button("Open Codex") {
                appModel.openCodexClient()
            }
            Button("Hook Manage") {
                withAnimation(.easeOut(duration: Layout.panelFadeDuration)) {
                    isPanelOpen = true
                    appModel.showHookManager()
                }
            }
            Button("Reset Position") {
                appModel.resetWindowPosition()
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var currentHeight: CGFloat {
        guard isPanelOpen else { return Layout.compactHeight }
        let measuredHeight = measuredPanelHeight
            + Layout.spriteHeight
            + Layout.stackSpacing
            + (Layout.verticalPadding * 2)
        return max(Layout.fallbackExpandedHeight, ceil(measuredHeight))
    }
}
