import MetalKit
import SwiftUI

struct SplatMapView: UIViewRepresentable {
    let store: SplatStore

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 30
        view.framebufferOnly = true
        view.isOpaque = true
        context.coordinator.renderer = SplatRenderer(view: view, store: store)
        view.delegate = context.coordinator.renderer
        store.setTheme(context.environment.colorScheme == .dark ? .dark : .light)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        store.setTheme(context.environment.colorScheme == .dark ? .dark : .light)
    }

    final class Coordinator {
        var renderer: SplatRenderer?
    }
}
