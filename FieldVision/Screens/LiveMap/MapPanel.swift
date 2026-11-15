import SwiftUI

/// The live 3D map, kept minimal: greys, a faint path and red only for danger, with a yellow edge while guidance can't be trusted.
/// VoiceOver reads it as sentences about what is around.
struct MapPanel: View {
    @Environment(GuideEngine.self) private var engine

    private var isWarning: Bool { engine.isRunning && !engine.isReliable }

    var body: some View {
        SplatMapView(store: engine.store)
            .overlay {
                if isWarning {
                    Color.yellow
                        .opacity(0.08)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
            .overlay {
                if isWarning {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.yellow, lineWidth: 3)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(InterfaceText.mapLabel(in: engine.language))
            .accessibilityValue(MapDescription.text(for: engine))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
