import ARKit
import SwiftUI

struct ARCameraView: UIViewRepresentable {
    @Environment(GuideEngine.self) private var engine

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        engine.attachCamera(view)
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
