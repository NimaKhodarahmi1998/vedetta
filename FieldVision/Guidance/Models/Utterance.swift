/// What the guide says or plays at one moment: a spoken line, a sound and vibration cue, or both.
nonisolated struct Utterance {
    let text: String?
    let cue: Cue?
    let interrupts: Bool
    let language: Language
}
