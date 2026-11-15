import AVFoundation

/// Synthesized once at launch, with the same recipes as the web concept.
final class SoundBank {
    private enum Waveform {
        case sine, triangle, square, saw

        func sample(at phase: Float) -> Float {
            switch self {
                case .sine:
                    return sin(phase)
                case .triangle:
                    return 2 / .pi * asin(sin(phase))
                case .square:
                    return sin(phase) >= 0 ? 1 : -1
                case .saw:
                    let cycle = phase / (2 * .pi)
                    return 2 * (cycle - floor(cycle + 0.5))
            }
        }
    }

    private struct Tone {
        let frequency: Float
        let waveform: Waveform
        let startTime: Float
        let attack: Float
        let decay: Float
        let peak: Float
        var endFrequency: Float?
        var lowPassCutoff: Float?
    }

    private static let sampleRate: Float = 44_100
    private static let envelopeFloor: Float = 0.0001
    private static let mixGain: Float = 0.8

    private let engine: AVAudioEngine
    private let players: [Cue: AVAudioPlayerNode]
    private let buffers: [Cue: AVAudioPCMBuffer]

    init() {
        let engine = AVAudioEngine()
        var players: [Cue: AVAudioPlayerNode] = [:]
        var buffers: [Cue: AVAudioPCMBuffer] = [:]
        if let format = AVAudioFormat(standardFormatWithSampleRate: Double(SoundBank.sampleRate), channels: 1) {
            for cue in Cue.allCases {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                players[cue] = player
                buffers[cue] = SoundBank.render(SoundBank.tones(for: cue), format: format)
            }
        }
        engine.mainMixerNode.outputVolume = 0.9
        self.engine = engine
        self.players = players
        self.buffers = buffers
    }

    func start() {
        if !engine.isRunning {
            try? engine.start()
        }
        for player in players.values where !player.isPlaying {
            player.play()
        }
    }

    /// A running engine plays silence, which would keep the app awake in the background.
    func stop() {
        engine.stop()
    }

    func play(_ cue: Cue) {
        guard let player = players[cue], let buffer = buffers[cue] else { return }

        if !engine.isRunning {
            start()
        }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    private static func tones(for cue: Cue) -> [Tone] {
        switch cue {
            case .tick:
                return [Tone(frequency: 2200, waveform: .sine, startTime: 0, attack: 0.002, decay: 0.035, peak: 0.07)]
            case .knock:
                return [
                    Tone(frequency: 160, waveform: .sine, startTime: 0, attack: 0.004, decay: 0.2, peak: 0.75, endFrequency: 85),
                    Tone(frequency: 320, waveform: .triangle, startTime: 0, attack: 0.002, decay: 0.06, peak: 0.2)
                ]
            case .flutter:
                return (0..<3).map {
                    Tone(frequency: 1300, waveform: .sine, startTime: Float($0) * 0.075, attack: 0.003, decay: 0.045, peak: 0.18)
                }
            case .fast:
                return (0..<2).map {
                    Tone(frequency: 940, waveform: .square, startTime: Float($0) * 0.22, attack: 0.005, decay: 0.15, peak: 0.25, lowPassCutoff: 3200)
                }
            case .long:
                return (0..<2).map {
                    Tone(frequency: 110, waveform: .saw, startTime: Float($0) * 0.62, attack: 0.02, decay: 0.45, peak: 0.36, lowPassCutoff: 750)
                }
            case .rising:
                return [
                    Tone(frequency: 440, waveform: .triangle, startTime: 0, attack: 0.004, decay: 0.13, peak: 0.38),
                    Tone(frequency: 660, waveform: .triangle, startTime: 0.17, attack: 0.004, decay: 0.15, peak: 0.38)
                ]
            case .proximity:
                return [Tone(frequency: 1500, waveform: .sine, startTime: 0, attack: 0.003, decay: 0.07, peak: 0.22)]
            case .torch:
                return [
                    Tone(frequency: 1800, waveform: .square, startTime: 0, attack: 0.001, decay: 0.014, peak: 0.25, lowPassCutoff: 5000),
                    Tone(frequency: 1400, waveform: .square, startTime: 0.07, attack: 0.001, decay: 0.014, peak: 0.22, lowPassCutoff: 5000)
                ]
            case .step:
                return [
                    Tone(frequency: 220, waveform: .triangle, startTime: 0, attack: 0.004, decay: 0.1, peak: 0.55),
                    Tone(frequency: 330, waveform: .triangle, startTime: 0.13, attack: 0.004, decay: 0.1, peak: 0.55)
                ]
        }
    }

    private static func render(_ tones: [Tone], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = (tones.map { $0.startTime + $0.attack + $0.decay }.max() ?? 0.1) + 0.05
        let frameCapacity = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity),
              let channel = buffer.floatChannelData?[0] else { return nil }

        buffer.frameLength = frameCapacity
        let frameCount = Int(frameCapacity)
        channel.update(repeating: 0, count: frameCount)
        for tone in tones {
            mix(tone, into: channel, frameCount: frameCount)
        }
        return buffer
    }

    private static func mix(_ tone: Tone, into channel: UnsafeMutablePointer<Float>, frameCount: Int) {
        let firstFrame = Int(tone.startTime * sampleRate)
        let length = Int((tone.attack + tone.decay) * sampleRate)
        let smoothing: Float? = tone.lowPassCutoff.map { 1 - exp(-2 * .pi * $0 / sampleRate) }
        var phase: Float = 0
        var filtered: Float = 0
        for offset in 0..<length {
            let time = Float(offset) / sampleRate
            let frequency: Float = tone.endFrequency.map {
                tone.frequency * pow($0 / tone.frequency, time / (tone.attack + tone.decay))
            } ?? tone.frequency
            phase += 2 * .pi * frequency / sampleRate

            var sample = tone.waveform.sample(at: phase)
            if let smoothing {
                filtered += smoothing * (sample - filtered)
                sample = filtered
            }

            let envelope: Float = time < tone.attack
                ? envelopeFloor * pow(tone.peak / envelopeFloor, time / tone.attack)
                : tone.peak * pow(envelopeFloor / tone.peak, (time - tone.attack) / tone.decay)
            let frame = firstFrame + offset
            if frame < frameCount {
                channel[frame] += sample * envelope * mixGain
            }
        }
    }
}
