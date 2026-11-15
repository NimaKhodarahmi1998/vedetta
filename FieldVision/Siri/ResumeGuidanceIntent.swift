import AppIntents

/// "Back to Vedetta": the answer to the question asked after leaving the app, so it goes straight back to guiding.
struct ResumeGuidanceIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Resume Guidance"
    nonisolated static let description = IntentDescription("Opens Vedetta and goes back to guiding you.")
    nonisolated static let openAppWhenRun = true

    @available(iOS 26, *)
    nonisolated static var supportedModes: IntentModes { .foreground }

    @Dependency private var engine: GuideEngine

    @MainActor
    func perform() async throws -> some IntentResult {
        if !engine.isRunning { engine.start() }
        return .result()
    }
}
