import AppIntents

nonisolated struct FieldVisionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartGuidanceIntent(),
            phrases: [
                "I'm going out with \(.applicationName)",
                "Start \(.applicationName)",
                "Guide me with \(.applicationName)",
            ],
            shortTitle: "Start Guidance",
            systemImageName: "figure.walk"
        )
        AppShortcut(
            intent: ResumeGuidanceIntent(),
            phrases: [
                "Back to \(.applicationName)",
                "Resume \(.applicationName)",
            ],
            shortTitle: "Resume Guidance",
            systemImageName: "arrow.uturn.backward"
        )
    }
}
