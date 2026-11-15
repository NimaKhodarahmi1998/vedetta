/// Every line of interface copy, in Italian and English. The spoken lines are in SpokenLine.
enum InterfaceText {
    static func arUnsupported(in language: Language) -> String {
        language.text("Questo iPhone non supporta ARKit.", "This iPhone doesn't support ARKit.")
    }

    static func torchNearOnly(in language: Language) -> String {
        language.text("Torcia accesa: vedo solo vicino", "Torch on: I only see close by")
    }

    static func unreliable(_ reason: UnreliableReason?, in language: Language) -> String {
        guard let reason else { return language.text("Guida non affidabile", "Guidance unreliable") }
        return SpokenLine.unreliable(reason, in: language)
    }

    static func mapLabel(in language: Language) -> String {
        language.text("Mappa 3D dal vivo", "Live 3D map")
    }

    static func cameraLabel(in language: Language) -> String {
        language.text("Fotocamera", "Camera")
    }

    static func lastMessage(_ caption: String, in language: Language) -> String {
        guard !caption.isEmpty else { return language.text("Ancora nessun avviso", "No messages yet") }
        return language.text("Ultimo avviso: ", "Last message: ") + caption
    }

    static func startPrompt(in language: Language) -> String {
        language.text("Vuoi avviare la guida?", "Start Guidance?")
    }

    static func notNow(in language: Language) -> String {
        language.text("Non ora", "Not Now")
    }

    static func leftAppTitle(in language: Language) -> String {
        language.text("Vuoi tornare alla guida?", "Go Back to Guidance?")
    }

    static func leftAppBody(in language: Language) -> String {
        language.text(
            "La guida è in pausa. Tocca qui o di' «Ehi Siri, torna a Vedetta».",
            "Guidance is paused. Tap here or say “Hey Siri, back to Vedetta.”"
        )
    }

    static func backToGuidance(in language: Language) -> String {
        language.text("Torna alla guida", "Back to Guidance")
    }

    static func start(in language: Language) -> String {
        language.text("Avvia", "Start")
    }

    static func pause(in language: Language) -> String {
        language.text("Pausa", "Pause")
    }

    static func mark(in language: Language) -> String {
        language.text("Segna", "Mark")
    }

    static func howItWorks(in language: Language) -> String {
        language.text("Come funziona", "How it works")
    }

    static func markObstacle(in language: Language) -> String {
        language.text("Segna ostacolo", "Mark obstacle")
    }

    static func voice(isOn: Bool, in language: Language) -> String {
        isOn ? language.text("Disattiva la voce", "Turn Off Voice") : language.text("Attiva la voce", "Turn On Voice")
    }
}
