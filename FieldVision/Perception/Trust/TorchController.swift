import ARKit
import AVFoundation

/// Switches the iPhone torch on in the dark and off when real light is back.
///
/// Torch-lit frames can't tell whether it is light again, so every 5 s the torch goes off for about
/// a quarter of a second (a probe) and the real light is measured on those frames.
///
/// It only switches on after guidance has said it can't see because of the dark (mayTurnOn), so a hand on the lens
/// is never answered with the torch first, and it only counts as on once the torch really is on.
nonisolated final class TorchController {
    nonisolated enum Phase {
        case off, on, probing
    }

    // Luma is 0...255, ambient intensity is ARKit's estimate in lumens.
    private static let darkAmbientIntensity: Float = 45
    private static let darkLuma: Float = 26
    private static let lightLuma: Float = 55
    private static let probeInterval = 5.0
    private static let probeDuration = 0.28

    private(set) var phase: Phase = .off
    /// True when the torch turns on, false when it turns off because light is back.
    var onChange: ((Bool) -> Void)?

    private let device: AVCaptureDevice?
    private var darkDuration = 0.0
    private var lastSwitchTime = -99.0
    private var lastAttemptTime = -99.0
    private var probeStartTime = 0.0
    private var lastProbeTime = 0.0
    private var probeSamples: [Float] = []

    var isOn: Bool { phase != .off }
    /// When the torch last switched on or off.
    var switchTime: Double { lastSwitchTime }
    var isAvailable: Bool { device?.hasTorch == true }
    /// Frames taken while the torch is briefly off, which the rest of the pipeline ignores.
    var isProbing: Bool { phase == .probing }

    init() {
        device = ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    /// Auto-exposure needs a moment after the torch switches, so the picture isn't judged yet.
    func isSettling(at time: Double) -> Bool {
        time - lastSwitchTime < 0.7
    }

    func update(time: Double, delta: Double, ambientIntensity: Float?, lumaMean: Float, mayTurnOn: Bool) {
        guard isAvailable else { return }
        switch phase {
            case .off:
                let isDark = (ambientIntensity.map { $0 < Self.darkAmbientIntensity } ?? false) || lumaMean < Self.darkLuma
                darkDuration = isDark ? darkDuration + delta : 0
                if mayTurnOn && darkDuration > 0.25 && time - lastSwitchTime > 1.5 && time - lastAttemptTime > 1.5 {
                    lastAttemptTime = time
                    // A torch that didn't light says nothing.
                    guard setTorch(on: true) else { return }
                    phase = .on
                    lastSwitchTime = time
                    lastProbeTime = time
                    onChange?(true)
                }
            case .on:
                if time - lastProbeTime > Self.probeInterval && time - lastSwitchTime > 2 {
                    setTorch(on: false)
                    phase = .probing
                    probeStartTime = time
                    probeSamples = []
                }
            case .probing:
                // Lets the torch light fade first.
                if time - probeStartTime > 0.12 { probeSamples.append(lumaMean) }
                if time - probeStartTime > Self.probeDuration {
                    let mean = probeSamples.isEmpty ? 0 : probeSamples.reduce(0, +) / Float(probeSamples.count)
                    lastProbeTime = time
                    if mean > Self.lightLuma {
                        phase = .off
                        darkDuration = 0
                        lastSwitchTime = time
                        onChange?(false)
                    } else if setTorch(on: true) {
                        phase = .on
                    } else {
                        // It didn't come back on: guidance goes on without it.
                        phase = .off
                        darkDuration = 0
                        lastSwitchTime = time
                    }
                }
        }
    }

    /// On pause or restart.
    func forceOff() {
        if phase != .off { setTorch(on: false) }
        phase = .off
        darkDuration = 0
    }

    /// Reads the torch back: true only if it really is in the state asked for.
    @discardableResult
    private func setTorch(on isOn: Bool) -> Bool {
        guard let device, device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if isOn {
                try device.setTorchModeOn(level: min(1.0, AVCaptureDevice.maxAvailableTorchLevel))
            } else {
                device.torchMode = .off
            }
            return device.torchMode == (isOn ? .on : .off)
        } catch {
            // The torch is a help, never a requirement: guidance goes on without it.
            return false
        }
    }
}
