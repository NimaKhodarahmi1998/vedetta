nonisolated enum UnreliableReason: String {
    case dark, bright, covered, motion, features, tracking, stale, relocalizing

    func text(in language: Language) -> String {
        switch self {
            case .dark: language.text("troppo buio", "too dark")
            case .bright: language.text("troppa luce", "too much light")
            case .covered: language.text("obiettivo coperto", "camera covered")
            case .motion: language.text("telefono troppo mosso", "phone moving too much")
            case .features: language.text("superficie liscia davanti", "plain surface ahead")
            case .tracking: language.text("orientamento perso", "tracking lost")
            case .stale: language.text("immagine bloccata", "camera frozen")
            case .relocalizing: language.text("sto riconoscendo il posto", "recognising the place")
        }
    }
}
