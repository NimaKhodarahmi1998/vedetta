import SwiftUI

/// The status up top and the controls in the bottom bar.
struct GuideToolbar: ToolbarContent {
    let engine: GuideEngine
    /// Opens the onboarding again («Come funziona»).
    let showGuide: () -> Void

    var body: some ToolbarContent {
        let language = engine.language

        ToolbarItem(placement: .principal) {
            StatusLabel()
        }

        ToolbarItemGroup(placement: .bottomBar) {
            Button(InterfaceText.howItWorks(in: language), systemImage: "questionmark.circle") {
                showGuide()
            }

            Button(
                InterfaceText.voice(isOn: engine.isVoiceOn, in: language),
                systemImage: engine.isVoiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill"
            ) {
                engine.isVoiceOn.toggle()
            }

            Spacer()

            Button {
                engine.isRunning ? engine.pause() : engine.start()
            } label: {
                Label(
                    engine.isRunning ? InterfaceText.pause(in: language) : InterfaceText.start(in: language),
                    systemImage: engine.isRunning ? "pause.fill" : "play.fill"
                )
                .labelStyle(.titleAndIcon)
            }
            .glassButton(isProminent: true)
        }
    }
}
