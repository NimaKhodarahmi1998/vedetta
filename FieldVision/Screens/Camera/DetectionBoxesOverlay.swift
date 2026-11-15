import SwiftUI

/// A box around each tracked person or vehicle in the camera picture, named when it matters.
struct DetectionBoxesOverlay: View {
    @Environment(GuideEngine.self) private var engine
    let size: CGSize

    var body: some View {
        let transform = engine.displayTransform(for: size)
        ZStack(alignment: .topLeading) {
            ForEach(engine.boxes) { box in
                let normalized = box.rect.applying(transform)
                let frame = CGRect(
                    x: normalized.minX * size.width,
                    y: normalized.minY * size.height,
                    width: normalized.width * size.width,
                    height: normalized.height * size.height
                )
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        box.style.color.opacity(box.text.isEmpty ? 0.45 : 1),
                        style: StrokeStyle(lineWidth: box.text.isEmpty ? 1 : 2, dash: box.style.dash)
                    )
                    .frame(width: max(4, frame.width), height: max(4, frame.height))
                    .overlay(alignment: .topLeading) {
                        if !box.text.isEmpty {
                            MarkerLabel(text: box.text, style: box.style)
                                .alignmentGuide(.top) { $0[.bottom] + 4 }
                        }
                    }
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
