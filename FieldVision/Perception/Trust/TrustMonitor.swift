import ARKit

/// The weakest signal sets the trust. Warns fast (0.3 s below the threshold), clears slowly (1 s above it).
nonisolated final class TrustMonitor {
    static let threshold: Float = 0.45

    private(set) var trust: Float = 1
    private(set) var isReliable = true
    private(set) var reason: UnreliableReason?
    private(set) var weakestSignal: UnreliableReason = .tracking
    var onChange: ((Bool, UnreliableReason?) -> Void)?

    private var timeBelowThreshold = 0.0
    private var timeAboveThreshold = 0.0
    private var lastUpdateTime: Double?

    func update(time: Double, input: TrustInput) {
        let delta = lastUpdateTime.map { min(0.2, max(0, time - $0)) } ?? 0
        lastUpdateTime = time

        var signals = [Self.trackingSignal(for: input.trackingState)]
        // First in the list, so a covered lens wins over darkness when both read zero.
        if input.isLensCovered { signals.insert((value: 0, reason: .covered), at: 0) }
        if let ambientIntensity = input.ambientIntensity, !input.isTorchOn {
            signals.append((value: ((ambientIntensity - 10) / 77).clamped(to: 0...1), reason: .dark))
        }
        signals.append((value: ((input.lumaMean - 12) / 31).clamped(to: 0...1), reason: .dark))
        signals.append((value: ((250 - input.lumaMean) / 30).clamped(to: 0...1), reason: .bright))
        let contrast = ((input.lumaDeviation - 4) / 14).clamped(to: 0...1)
        signals.append((value: contrast, reason: input.lumaMean < 70 ? .covered : .features))

        let weakest = signals.min { $0.value < $1.value } ?? (value: 1, reason: .tracking)
        weakestSignal = weakest.reason
        trust += (weakest.value - trust) * Float(min(1, delta * 8))

        if isReliable {
            timeBelowThreshold = trust < Self.threshold ? timeBelowThreshold + delta : 0
            if timeBelowThreshold >= 0.3 {
                isReliable = false
                reason = weakest.reason
                timeAboveThreshold = 0
                onChange?(false, reason)
            }
        } else {
            timeAboveThreshold = trust >= Self.threshold ? timeAboveThreshold + delta : 0
            if trust < Self.threshold { reason = weakest.reason }
            if timeAboveThreshold >= 1.0 {
                isReliable = true
                timeBelowThreshold = 0
                reason = nil
                onChange?(true, nil)
            }
        }
    }

    /// For the watchdog, when camera frames stop arriving.
    func forceUnreliable(_ reason: UnreliableReason) {
        trust = 0
        self.reason = reason
        guard isReliable else { return }
        isReliable = false
        timeAboveThreshold = 0
        onChange?(false, reason)
    }

    func reset() {
        trust = 1
        isReliable = true
        reason = nil
        timeBelowThreshold = 0
        timeAboveThreshold = 0
        lastUpdateTime = nil
    }

    private static func trackingSignal(for state: ARCamera.TrackingState) -> (value: Float, reason: UnreliableReason) {
        switch state {
            case .normal:
                return (1, .tracking)
            case .notAvailable:
                return (0, .tracking)
            case .limited(.excessiveMotion):
                return (0.2, .motion)
            case .limited(.insufficientFeatures):
                return (0.35, .features)
            case .limited(.relocalizing):
                return (0.4, .relocalizing)
            case .limited(.initializing):
                return (0.6, .tracking)
            case .limited:
                return (0.4, .tracking)
        }
    }
}
