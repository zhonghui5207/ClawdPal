import ClawdPetCore
import AppKit
import SwiftUI

struct PetOverlayView: View {
    @ObservedObject var appModel: AppModel
    @State private var isPanelOpen = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 6) {
                if isPanelOpen {
                    ControlPanelView(appModel: appModel)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                StatusBubbleView(text: appModel.bubbleText)
                    .frame(maxWidth: 260)

                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        isPanelOpen.toggle()
                    }
                } label: {
                    PetSpriteView(mood: appModel.mood)
                        .frame(width: 210, height: 150)
                }
                .buttonStyle(.plain)
                .help("Open ClawdPet panel")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .frame(width: 320, height: 260, alignment: .bottom)
        .background(Color.clear)
        .contextMenu {
            Button("Jump Back") {
                appModel.jumpBackToTerminal()
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
}
