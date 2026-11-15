import SwiftUI

/// The last spoken line as Apple-style subtitles, with the sound cue in brackets above it.
struct SubtitlesOverlay: View {
    @Environment(GuideEngine.self) private var engine

    var body: some View {
        VStack(spacing: 4) {
            if let cue = engine.subtitleCue?.subtitle(in: engine.language) {
                line("[\(cue)]")
            }
            if !engine.caption.isEmpty {
                line(engine.caption)
            }
        }
        .multilineTextAlignment(.center)
        .allowsHitTesting(false)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(.black.opacity(0.75), in: .rect(cornerRadius: 6))
    }
}
