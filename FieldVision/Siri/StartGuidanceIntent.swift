import AppIntents

/// "I'm going out with Vedetta": Siri asks to start, then the app opens already guiding.
struct StartGuidanceIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Start Guidance"
    nonisolated static let description = IntentDescription("Opens Vedetta and starts guiding you right away.")
    nonisolated static let openAppWhenRun = true

    @available(iOS 26, *)
    nonisolated static var supportedModes: IntentModes { .foreground }

    @Dependency private var engine: GuideEngine

    @MainActor
    func perform() async throws -> some IntentResult {
        engine.isSiriAsking = true
        defer { engine.isSiriAsking = false }
        try await requestConfirmation(actionName: .start, dialog: "Do you want me to start Vedetta?")
        if !engine.isRunning { engine.start() }
        return .result()
    }
}
