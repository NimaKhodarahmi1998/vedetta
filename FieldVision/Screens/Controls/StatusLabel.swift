import SwiftUI

/// Shown only when it matters: why guidance can't be trusted, or that the torch limits it to close by.
struct StatusLabel: View {
    @Environment(GuideEngine.self) private var engine

    var body: some View {
        Group {
            if !engine.isReliable {
                Label {
                    Text(InterfaceText.unreliable(engine.reason, in: engine.language))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
            } else if engine.isTorchOn {
                Label(InterfaceText.torchNearOnly(in: engine.language), systemImage: "flashlight.on.fill")
            }
        }
        .font(.subheadline.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
