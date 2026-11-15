import SwiftUI

/// The camera, with what the detector sees and what the guide says. VoiceOver reads it as the last thing said.
struct CameraPanel: View {
    @Environment(GuideEngine.self) private var engine
    @State private var size = CGSize.zero

    var body: some View {
        ARCameraView()
            .overlay {
                DetectionBoxesOverlay(size: size)
            }
            .overlay(alignment: .bottom) {
                SubtitlesOverlay()
                    .padding(16)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .background(.black)
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
            .environment(\.colorScheme, .dark)
            // Testers mark real moments here, without a test button on screen.
            .onTapGesture(count: 3, perform: engine.mark)
            // A long press marks the obstacle ahead so it is remembered here; another on the same spot removes it.
            .onLongPressGesture(minimumDuration: 0.8, perform: engine.markObstacle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(InterfaceText.cameraLabel(in: engine.language))
            .accessibilityValue(InterfaceText.lastMessage(engine.caption, in: engine.language))
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityAction(named: InterfaceText.mark(in: engine.language), engine.mark)
            .accessibilityAction(named: InterfaceText.markObstacle(in: engine.language), engine.markObstacle)
    }
}
