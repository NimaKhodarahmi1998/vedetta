import SwiftUI

struct ContentView: View {
    @Environment(GuideEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverOn
    @State private var isAskingToStart = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var isShowingOnboarding = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                CameraPanel()
                MapPanel()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                GuideToolbar(engine: engine) { isShowingOnboarding = true }
            }
        }
        .alert(InterfaceText.startPrompt(in: engine.language), isPresented: $isAskingToStart) {
            Button(InterfaceText.start(in: engine.language), action: engine.start)
                .keyboardShortcut(.defaultAction)
            Button(InterfaceText.notNow(in: engine.language), role: .cancel) {}
        }
        // Every time the app opens, it offers to start, so nobody has to find the button.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active && !engine.isRunning && !engine.isSiriAsking && !isShowingOnboarding else { return }
            // The first time, the onboarding comes first; it ends by starting guidance.
            if hasSeenOnboarding { isAskingToStart = true } else { isShowingOnboarding = true }
        }
        .onChange(of: isShowingOnboarding) { _, isShowing in
            if isShowing && engine.isRunning { engine.pause() }
        }
        .fullScreenCover(isPresented: $isShowingOnboarding) {
            OnboardingView { startsGuidance in
                hasSeenOnboarding = true
                isShowingOnboarding = false
                if startsGuidance { engine.start() } else { isAskingToStart = true }
            }
            .environment(engine)
        }
        .onChange(of: isAskingToStart) { _, isAsking in
            // VoiceOver reads the alert itself.
            if isAsking && !isVoiceOverOn { engine.speak(InterfaceText.startPrompt(in: engine.language)) }
        }
        .onChange(of: engine.isRunning) { _, isRunning in
            if isRunning { isAskingToStart = false }
        }
        .onChange(of: engine.isSiriAsking) { _, isSiriAsking in
            if isSiriAsking { isAskingToStart = false }
        }
        .overlay {
            if !engine.isARSupported {
                Text(InterfaceText.arUnsupported(in: engine.language))
                    .font(.headline)
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 20))
            }
        }
    }
}
