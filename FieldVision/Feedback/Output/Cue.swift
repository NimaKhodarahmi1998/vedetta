/// One sound and vibration pattern per meaning.
nonisolated enum Cue: CaseIterable {
    case tick, knock, flutter, fast, long, rising, proximity, torch, step

    /// The sound's name for the subtitles; none for the steady tick, which would flood them.
    func subtitle(in language: Language) -> String? {
        switch self {
            case .tick: nil
            case .knock: language.text("Un colpo", "One knock")
            case .flutter: language.text("Fremito", "Flutter")
            case .fast: language.text("Due impulsi forti", "Two strong pulses")
            case .long: language.text("Lungo-lungo", "Long-long")
            case .rising: language.text("Due colpi in salita", "Two rising knocks")
            case .proximity: language.text("Bip sempre più rapidi", "Faster beeps")
            case .torch: language.text("Clic-clic", "Click-click")
            case .step: language.text("Due tocchi bassi", "Two low taps")
        }
    }
}
