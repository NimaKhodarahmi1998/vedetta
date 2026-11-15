import AppIntents
import SwiftUI

@main
struct FieldVisionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine: GuideEngine

    init() {
        let engine = GuideEngine()
        _engine = State(initialValue: engine)
        AppDependencyManager.shared.add(dependency: engine)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .onChange(of: scenePhase) { _, phase in
                    engine.sceneDidChange(to: phase)
                }
        }
    }
}
