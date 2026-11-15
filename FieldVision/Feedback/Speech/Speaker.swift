import AVFoundation
import SwiftUI

final class Speaker {
    private let synthesizer = AVSpeechSynthesizer()
    private var voices: [Language: AVSpeechSynthesisVoice] = [:]

    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    func say(_ text: String, language: Language, interrupts: Bool) {
        guard !UIAccessibility.isVoiceOverRunning else {
            announce(text, interrupts: interrupts)
            return
        }
        if interrupts && synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: language)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 1.08)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// With VoiceOver on, the guide speaks through VoiceOver, in the voice, speed and language the person chose and
    /// never over it; urgent lines cut in.
    private func announce(_ text: String, interrupts: Bool) {
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = interrupts ? .high : .default
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func voice(for language: Language) -> AVSpeechSynthesisVoice? {
        if let voice = voices[language] { return voice }
        let voice = bestVoice(for: language)
        voices[language] = voice
        return voice
    }

    /// The most natural voice installed: Premium, then Enhanced, and in Italian Alice, the web prototype's voice.
    private func bestVoice(for language: Language) -> AVSpeechSynthesisVoice? {
        let systemDefault = AVSpeechSynthesisVoice(language: language.voiceCode)
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == language.voiceCode && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        func score(_ voice: AVSpeechSynthesisVoice) -> Int {
            voice.quality.rawValue * 4
                + (language == .italian && voice.name.hasPrefix("Alice") ? 2 : 0)
                + (voice.identifier == systemDefault?.identifier ? 1 : 0)
        }
        return candidates.max { score($0) < score($1) } ?? systemDefault
    }
}
