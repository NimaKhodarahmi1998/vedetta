/// Plays what the guide decides: the voice, the sounds and the vibrations.
final class FeedbackPlayer {
    private let speaker = Speaker()
    private let sounds = SoundBank()
    private let haptics = HapticBank()
    private var isPrepared = false

    func prepare() {
        if !isPrepared {
            isPrepared = true
            speaker.configureAudioSession()
        }
        sounds.start()
    }

    func play(_ cue: Cue) {
        sounds.play(cue)
        haptics.play(cue)
    }

    func say(_ text: String, language: Language, interrupts: Bool) {
        speaker.say(text, language: language, interrupts: interrupts)
    }

    func stopSpeaking() {
        speaker.stop()
    }

    func stopSounds() {
        sounds.stop()
    }
}
