import CoreHaptics

final class HapticBank {
    private let engine: CHHapticEngine?
    private let patterns: [Cue: CHHapticPattern]

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine() else {
            self.engine = nil
            self.patterns = [:]
            return
        }

        engine.isAutoShutdownEnabled = true
        engine.resetHandler = HapticBank.restartHandler(for: engine)
        self.engine = engine
        self.patterns = Cue.allCases.reduce(into: [:]) { patterns, cue in
            patterns[cue] = try? CHHapticPattern(events: HapticBank.events(for: cue), parameters: [])
        }
    }

    func play(_ cue: Cue) {
        guard let engine, let pattern = patterns[cue] else { return }

        do {
            try engine.start()
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            // A missed vibration is harmless: the sound still plays
        }
    }

    private nonisolated static func restartHandler(for engine: CHHapticEngine) -> () -> Void {
        { [weak engine] in try? engine?.start() }
    }

    private static func events(for cue: Cue) -> [CHHapticEvent] {
        switch cue {
            case .tick:
                [transient(at: 0, intensity: 0.25, sharpness: 0.9)]
            case .knock:
                [transient(at: 0, intensity: 1.0, sharpness: 0.35)]
            case .flutter:
                [
                    transient(at: 0, intensity: 0.5, sharpness: 0.8),
                    transient(at: 0.075, intensity: 0.5, sharpness: 0.8),
                    transient(at: 0.15, intensity: 0.5, sharpness: 0.8)
                ]
            case .fast:
                [
                    continuous(at: 0, duration: 0.15, intensity: 1, sharpness: 1),
                    continuous(at: 0.22, duration: 0.15, intensity: 1, sharpness: 1)
                ]
            case .long:
                [
                    continuous(at: 0, duration: 0.45, intensity: 0.8, sharpness: 0.15),
                    continuous(at: 0.62, duration: 0.45, intensity: 0.8, sharpness: 0.15)
                ]
            case .rising:
                [
                    transient(at: 0, intensity: 0.5, sharpness: 0.5),
                    transient(at: 0.17, intensity: 1.0, sharpness: 0.7)
                ]
            case .proximity:
                [transient(at: 0, intensity: 0.6, sharpness: 0.9)]
            case .torch:
                [
                    transient(at: 0, intensity: 0.45, sharpness: 1.0),
                    transient(at: 0.07, intensity: 0.45, sharpness: 1.0)
                ]
            case .step:
                [
                    transient(at: 0, intensity: 0.75, sharpness: 0.15),
                    transient(at: 0.13, intensity: 0.75, sharpness: 0.15)
                ]
        }
    }

    private static func transient(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: parameters(intensity: intensity, sharpness: sharpness),
            relativeTime: time
        )
    }

    private static func continuous(at time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: parameters(intensity: intensity, sharpness: sharpness),
            relativeTime: time,
            duration: duration
        )
    }

    private static func parameters(intensity: Float, sharpness: Float) -> [CHHapticEventParameter] {
        [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        ]
    }
}
