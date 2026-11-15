import ARKit
import Observation
import SwiftUI

/// The guide as the screens see it: its controls and everything they show.
@Observable
final class GuideEngine {
    let store: SplatStore
    let language = Language.current
    let isARSupported = ARWorldTrackingConfiguration.isSupported
    private(set) var isRunning = false
    private(set) var isReliable = true
    private(set) var reason: UnreliableReason?
    private(set) var isTorchOn = false
    private(set) var caption = ""
    private(set) var subtitleCue: Cue?
    private(set) var boxes: [DetectionBox] = []
    private(set) var sceneItems: [SceneItem] = []
    private(set) var pathAhead: PathAhead?
    /// Siri is asking whether to start, so the app doesn't ask a second time.
    var isSiriAsking = false
    var isVoiceOn = true {
        didSet {
            if !isVoiceOn { player.stopSpeaking() }
        }
    }

    var session: ARSession { pipeline.session }

    @ObservationIgnored private let pipeline: GuidancePipeline
    @ObservationIgnored private let player = FeedbackPlayer()
    @ObservationIgnored private let reminder: ReturnReminder
    @ObservationIgnored private var wasGuidingWhenInterrupted = false
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var startedAt = ContinuousClock.now
    @ObservationIgnored private var markCount = 0

    init() {
        let store = SplatStore()
        self.store = store
        pipeline = GuidancePipeline(store: store, language: Language.current)
        reminder = ReturnReminder(language: Language.current)
        reminder.onResume = { [weak self] in self?.start() }
        pipeline.guide.onUtterance = { [weak self] utterance in
            Task { @MainActor in self?.present(utterance) }
        }
        pipeline.onStateChange = { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }
    }

    func start() {
        guard isARSupported else { return }
        player.prepare()
        pipeline.start(language: language)
        isRunning = true
        startedAt = .now
        UIApplication.shared.isIdleTimerDisabled = true
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.checkWatchdog()
            }
        }
        Task { await reminder.requestPermission() }
    }

    /// Guidance pauses whenever the app isn't in front. Actually leaving it while guiding is said aloud and
    /// followed by a notification that offers to go straight back.
    func sceneDidChange(to phase: ScenePhase) {
        switch phase {
            case .active:
                wasGuidingWhenInterrupted = false
                reminder.clear()
            case .inactive:
                guard isRunning else { return }
                pause()
                wasGuidingWhenInterrupted = true
            case .background:
                player.stopSounds()
                guard wasGuidingWhenInterrupted else { return }
                wasGuidingWhenInterrupted = false
                if !UIAccessibility.isVoiceOverRunning { speak(SpokenLine.leftApp(in: language)) }
                reminder.post(in: language)
            @unknown default:
                break
        }
    }

    func pause() {
        pipeline.pause()
        isTorchOn = false
        isRunning = false
        player.stopSpeaking()
        UIApplication.shared.isIdleTimerDisabled = false
        watchdog?.cancel()
        watchdog = nil
    }

    /// The tester marks a real moment (lens covered, person hidden) to measure the delay later.
    func mark() {
        markCount += 1
        pipeline.mark(markCount)
        player.prepare()
        player.play(.tick)
        store.sendWave()
    }

    /// A long press on the camera: marks the obstacle ahead, or takes away the mark there; remembered in this place.
    func markObstacle() {
        guard isRunning else { return }
        player.prepare()
        pipeline.markObstacle()
    }

    /// The onboarding plays each sound so the walker learns it by ear.
    func preview(_ cue: Cue) {
        player.prepare()
        player.play(cue)
    }

    func speak(_ text: String) {
        guard isVoiceOn else { return }
        player.prepare()
        player.say(text, language: language, interrupts: true)
    }

    /// The camera view takes over the session when it's created.
    func attachCamera(_ view: ARSCNView) {
        view.session = session
        pipeline.reclaimSessionDelegate()
    }

    func displayTransform(for size: CGSize) -> CGAffineTransform {
        guard size.width > 0, size.height > 0, let frame = session.currentFrame else { return .identity }
        return frame.displayTransform(for: .portrait, viewportSize: size)
    }

    /// Frames are expected from 2 s after the start.
    private func checkWatchdog() {
        guard isRunning, startedAt.duration(to: .now) > .seconds(2) else { return }
        pipeline.checkFrameWatchdog()
    }

    private func present(_ utterance: Utterance) {
        if let cue = utterance.cue { player.play(cue) }
        if let text = utterance.text {
            if isVoiceOn { player.say(text, language: utterance.language, interrupts: utterance.interrupts) }
            caption = text
            subtitleCue = utterance.cue
        } else if let cue = utterance.cue, cue != .tick {
            subtitleCue = cue
        }
        if utterance.cue == .tick { store.sendWave() }
    }

    private func apply(_ state: PipelineState) {
        boxes = state.boxes
        sceneItems = state.items
        pathAhead = state.pathAhead
        isReliable = state.isReliable
        reason = state.reason
        isTorchOn = isRunning && state.isTorchOn
    }
}
