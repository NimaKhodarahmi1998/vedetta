import ARKit
import QuartzCore
import simd

/// Runs the guide on every ARKit frame: the self-check, the 3D map, detections, depth, tracking and what to say.
nonisolated final class GuidancePipeline: NSObject, ARSessionDelegate, @unchecked Sendable {
    /// With the torch on, only what it lights is trusted.
    static let nearRange: Float = 5
    /// Nothing farther than this is tracked or named.
    static let maxRange: Float = 12
    /// At most this many labels on the map and on the camera.
    static let maxLabels = 4

    let session = ARSession()
    let store: SplatStore
    let guide: Guide
    let log = EventLog()
    var onStateChange: (@Sendable (PipelineState) -> Void)?

    let queue = DispatchQueue(label: "fieldvision.pipeline", qos: .userInteractive)
    let detector = Detector()
    let depthEstimator = DepthEstimator()
    let tracker = Tracker()
    let map = MapBuilder()
    let trustMonitor = TrustMonitor()
    let torch = TorchController()
    let shapes = SplatShapes.build()
    var depthScale = DepthScale()
    var walker = Walker()
    var planeGround: Float?
    var pointGround: Float?
    var pathAhead: PathAhead?
    var luma = LumaStats(mean: 120, deviation: 30)
    /// Last time the picture was lit and detailed with the torch off; a hand on the lens is a sudden drop from it.
    var lastLitTime = -99.0
    /// Set while the lens is taken to be covered.
    var coveredSince: Double?

    // Steps and stairs, out to 30 m (FloorSteps.swift); low objects close by (GuidancePipeline+Floor.swift);
    // dim light and darkness (LowLight.swift).
    let steps = StepReader()
    let stepSay = StepAnnouncer()
    let lowLight = LowLight()
    var floorScale = DepthScale()
    var stepViews: [StepView] = []
    var floorInfo: FloorInfo?
    var floorCandidate: (info: FloorInfo, time: Double)?
    var floorSaid: FloorKind?
    var floorClearTime = 0.0
    /// Where the floor visibly ends ahead (GuidancePipeline+Floor.swift): since when, and whether it was said.
    var floorEndSince: Double?
    var floorEndSaid = false
    /// Since when the floor in view ahead can't be checked; the "I can see" tick pauses meanwhile.
    var floorUncheckedSince: Double?
    var lastCamera: CameraSnapshot?
    /// Apple's classifier as a place hint (GuidancePipeline+Scene.swift).
    let scene = SceneClassifier()
    var isSceneBusy = false
    var lastSceneTime = 0.0
    var stairsVotes: [Bool] = []
    var stationVotes: [Bool] = []
    var isStairsLikely = false
    var isStationLikely = false
    var lastStairsHintTime = -99.0
    var lastSelfLogTime = -99.0
    /// Close walls and stairs going up (GuidancePipeline+PathAhead.swift).
    var hasSaidNearWall = false
    var lastWallSeen: (distance: Float, time: Double)?
    var lastStairsUpLineTime = -99.0
    /// Checks in a row in which the 3D map showed stairs going up.
    var stairsProfileHits = 0
    /// Points well below the floor ahead in the last floor check, and the last warning about a way down.
    var deepAhead: (count: Int, time: Double) = (0, -99)
    var lastDownWarningTime = -99.0
    /// Obstacles marked with a long press and the saved place they belong to (GuidancePipeline+Marks.swift).
    var marks: [UUID: SIMD3<Float>] = [:]
    var warnedMarks = Set<UUID>()
    var isLoadingPlace = false
    var relocalizationStart: Double?
    var lastPlaceSaveTime = -99.0
    var lastFloorDepthTime = 0.0

    var frameTime = 0.0
    var startTime = -1.0
    var isStartPending = false
    var frameCount = 0
    var lastDetectionTime = 0.0
    var lastDepthTime = 0.0
    var lastPublishTime = 0.0
    var lastMapSnapshotTime = 0.0
    var lastPathCheckTime = 0.0
    var lastGroundTime = 0.0
    var lastLogTime = 0.0
    var lastTickTime = -99.0
    var lastBuzzTime = -99.0
    var lastProximityTime = -99.0
    var isDetectorBusy = false
    var isDepthBusy = false
    var hasSaidAhead = false
    var hasSaidWall = false
    var saidOpening = PathOpening.none
    var pathClearTime = 0.0

    var rateWindowStart = 0.0
    var framesInWindow = 0
    var detectionsInWindow = 0
    var depthsInWindow = 0
    var framesPerSecond = 0.0
    var detectionRate = 0.0
    var detectionMilliseconds = 0.0
    var depthRate = 0.0
    var depthMilliseconds = 0.0

    private let frameClock = NSLock()
    private var lastFrameWallTime = CACurrentMediaTime()

    /// ARKit hands frames to this light queue; only the newest waits for the pipeline (see session(_:didUpdate:)).
    let frameQueue = DispatchQueue(label: "fieldvision.frames", qos: .userInteractive)
    private let pendingLock = NSLock()
    private var pendingFrame: ARFrame?
    private var isDraining = false

    init(store: SplatStore, language: Language) {
        self.store = store
        guide = Guide(log: log, language: language)
        super.init()
        session.delegate = self
        session.delegateQueue = frameQueue

        tracker.log = log
        tracker.onEvent = { [weak self] event in
            guard let self else { return }
            guide.handle(event, time: frameTime)
        }
        trustMonitor.onChange = { [weak self] isReliable, reason in
            guard let self else { return }
            guide.handle(isReliable ? .reliable(withTorch: torch.isOn) : .unreliable(reason ?? .dark), time: frameTime)
            lastTickTime = frameTime
            lastBuzzTime = frameTime
        }
        torch.onChange = { [weak self] isOn in
            guard let self else { return }
            guide.handle(isOn ? .torchOn : .torchOff, time: frameTime)
            log.write(["type": "torch", "on": .flag(isOn), "t": .number(frameTime), "luma": .number(Double(luma.mean))])
        }
    }

    func start(language: Language) {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.worldAlignment = .gravity
        configuration.isLightEstimationEnabled = true
        // The place saved with marks last time: ARKit tries to recognise it (GuidancePipeline+Marks.swift).
        let place = Self.savedPlace()
        configuration.initialWorldMap = place
        let isLoadingSavedPlace = place != nil
        reclaimSessionDelegate()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        queue.async { [self] in
            map.reset()
            tracker.reset()
            trustMonitor.reset()
            torch.forceOff()
            planeGround = nil
            pointGround = nil
            depthScale = DepthScale()
            startTime = -1
            isStartPending = true
            pathAhead = nil
            hasSaidAhead = false
            steps.reset()
            stepSay.reset()
            floorScale = DepthScale()
            stepViews = []
            floorInfo = nil
            floorCandidate = nil
            floorSaid = nil
            floorEndSince = nil
            floorEndSaid = false
            floorUncheckedSince = nil
            stairsVotes = []
            stationVotes = []
            isStairsLikely = false
            isStationLikely = false
            stepSay.isStairsLikely = false
            lowLight.reset()
            lastLitTime = -99
            coveredSince = nil
            marks = [:]
            warnedMarks = []
            isLoadingPlace = isLoadingSavedPlace
            relocalizationStart = nil
            store.setMap([])
        }
        frameClock.withLock { lastFrameWallTime = CACurrentMediaTime() }
        log.write(["type": "start", "lang": .text(language.rawValue), "version": "polish"])
        logSceneLabels()
        if let modelError = detector.loadError ?? depthEstimator.loadError {
            log.write(["type": "error", "message": .text(modelError)])
        }
    }

    func pause() {
        queue.async { [self] in torch.forceOff() }
        session.pause()
        log.write(["type": "pause"])
    }

    /// The tester marks a real moment (lens covered, person hidden) to measure the delay later.
    func mark(_ count: Int) {
        queue.async { [self] in
            log.write(["type": "mark", "n": .integer(count), "t": .number(frameTime)])
        }
    }

    /// The camera view takes over the session; the pipeline must stay its delegate.
    func reclaimSessionDelegate() {
        session.delegate = self
        session.delegateQueue = frameQueue
    }

    /// Frames stopped arriving: the camera is frozen.
    func checkFrameWatchdog() {
        let gap = frameClock.withLock { CACurrentMediaTime() - lastFrameWallTime }
        guard gap > 0.6 else { return }
        queue.async { [self] in trustMonitor.forceUnreliable(.stale) }
    }

    /// Only the newest frame waits: while the pipeline is busy, an older waiting frame is dropped. Frames never pile up,
    /// so ARKit never runs out of camera buffers (it stops the camera when the app holds too many frames) however long
    /// a moment of work takes.
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let startsDraining = pendingLock.withLock { () -> Bool in
            pendingFrame = frame
            guard !isDraining else { return false }
            isDraining = true
            return true
        }
        if startsDraining {
            queue.async { [self] in drainFrames() }
        }
    }

    private func drainFrames() {
        while let frame = pendingLock.withLock({ () -> ARFrame? in
            let next = pendingFrame
            pendingFrame = nil
            if next == nil { isDraining = false }
            return next
        }) {
            process(frame)
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        queue.async { [self] in
            updatePlanes(anchors)
            addMarks(from: anchors)
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        queue.async { [self] in updatePlanes(anchors) }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        queue.async { [self] in trustMonitor.forceUnreliable(.stale) }
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        log.write(["type": "error", "message": .text(error.localizedDescription)])
        queue.async { [self] in trustMonitor.forceUnreliable(.tracking) }
    }

    private func process(_ frame: ARFrame) {
        let time = frame.timestamp
        let delta = frameTime > 0 ? min(0.1, max(0, time - frameTime)) : 0
        frameTime = time
        frameClock.withLock { lastFrameWallTime = CACurrentMediaTime() }

        let camera = CameraSnapshot(transform: frame.camera.transform, intrinsics: frame.camera.intrinsics, resolution: frame.camera.imageResolution)
        lastCamera = camera
        followPlaceLoading(time: time)
        walker.position = camera.position
        let lookDirection = -SIMD3<Float>(camera.transform.columns.2.x, camera.transform.columns.2.y, camera.transform.columns.2.z)
        let flatDirection = SIMD2<Float>(lookDirection.x, lookDirection.z)
        if simd_length(flatDirection) > 0.2 { walker.forward = simd_normalize(flatDirection) }
        if startTime < 0 {
            startTime = time
            rateWindowStart = time
        }
        if isStartPending && time - startTime > 0.4 {
            isStartPending = false
            guide.handle(.start, time: time)
            lastTickTime = time
        }

        frameCount += 1
        framesInWindow += 1
        if torch.phase != .off || frameCount % 3 == 0 {
            luma = LumaSampler.stats(of: frame.capturedImage)
            lowLight.update(lumaMean: luma.mean)
        }
        let ambientIntensity = frame.lightEstimate.map { Float($0.ambientIntensity) }
        updateLensCover(time: time)
        // The torch is only tried once guidance has already said it can't see because of the dark.
        let mayTurnOn = !trustMonitor.isReliable && trustMonitor.reason == .dark && coveredSince == nil
        torch.update(time: time, delta: delta, ambientIntensity: torch.isOn ? nil : ambientIntensity, lumaMean: luma.mean, mayTurnOn: mayTurnOn)
        if !torch.isProbing && !torch.isSettling(at: time) {
            let input = TrustInput(
                trackingState: frame.camera.trackingState,
                ambientIntensity: ambientIntensity,
                lumaMean: luma.mean,
                lumaDeviation: luma.deviation,
                isTorchOn: torch.isOn,
                isLensCovered: coveredSince != nil
            )
            trustMonitor.update(time: time, input: input)
        }

        let isReliable = trustMonitor.isReliable
        let canLook = isReliable && !torch.isProbing
        let featurePoints = frame.rawFeaturePoints?.points ?? []
        if canLook, frameCount % 2 == 0, !featurePoints.isEmpty {
            addFeaturePoints(featurePoints, from: frame.capturedImage, camera: camera, time: time)
        }
        // In dim light both models get a brightened copy of the same picture (same geometry); in daylight the raw one.
        let gain = lowLight.gain
        let lowLight = self.lowLight
        let brighten: @Sendable (CVPixelBuffer) -> CVPixelBuffer? = { picture in lowLight.brightened(picture, gain: gain) }
        let prepare: (@Sendable (CVPixelBuffer) -> CVPixelBuffer?)? = gain > 1.01 ? brighten : nil
        if canLook && !isDetectorBusy && time - lastDetectionTime > 1.0 / 12.0 {
            requestDetections(in: frame.capturedImage, prepare: prepare, camera: camera, time: time)
        }
        if canLook && depthEstimator.isAvailable && !isDepthBusy && time - lastDepthTime > 1.0 / 6.0 {
            requestDepth(in: frame.capturedImage, prepare: prepare, camera: camera, featurePoints: featurePoints, time: time)
        } else if canLook && depthEstimator.isAvailable && !isDepthBusy && time - lastFloorDepthTime > 0.25 && time - lastDepthTime > 0.06,
                  let band = DepthBand.floor(cam: stepCamera(camera), h: DepthEstimator.croppedBand(for: camera.resolution).height) {
            // In between: the floor reader's own band of the picture, from just above the horizon down.
            requestFloorDepth(in: frame.capturedImage, camera: camera, featurePoints: featurePoints, band: band, gain: gain, time: time)
        }

        if canLook && !isSceneBusy && time - lastSceneTime > 1.0 {
            requestScene(in: frame.capturedImage, time: time)
        }

        tracker.tick(time: time, delta: delta, walker: walker, camera: camera, isReliable: isReliable)
        if time - lastGroundTime > 1 {
            lastGroundTime = time
            estimateGroundFromPoints()
        }
        if time - lastPathCheckTime > 0.2 {
            lastPathCheckTime = time
            analyzeFloor(time: time)
            analyzeSteps(time: time)
            analyzePathAhead(time: time)
            checkNearWall(time: time)
            checkMarks(time: time)
        }
        if isReliable {
            if time - lastTickTime >= 2 && !isStartPending && !isFloorUnchecked(at: time) {
                lastTickTime = time
                guide.handle(.tick, time: time)
            }
        } else if time - lastBuzzTime >= 4 {
            lastBuzzTime = time
            guide.handle(.buzz, time: time)
        }
        guide.flush(time: time)

        if time - lastMapSnapshotTime > 0.25 {
            lastMapSnapshotTime = time
            map.prune(around: walker.position)
            store.setMap(map.vertices())
        }
        store.setOverlay(overlaySplats(), walker: walker.position, forward: walker.forward, ground: ground, isReliable: isReliable)
        updateRates(time: time)
        if time - lastPublishTime > 1.0 / 12.0 {
            lastPublishTime = time
            publish(time: time)
        }
        if time - lastLogTime > 0.5 {
            lastLogTime = time
            logState(time: time)
        }
    }

    /// A hand on the lens turns a lit, detailed picture flat and black in a moment; a dark room fades instead.
    /// With the torch on and settled, a picture that is still flat (and lit) is a covered lens too: the torch goes off
    /// and that is said. The cover is let go when the picture shows detail again, or after 8 s, so the torch can test
    /// a real blackout.
    private func updateLensCover(time: Double) {
        let isFlat = luma.deviation < 8
        if torch.phase == .off && luma.mean > 45 && luma.deviation > 12 { lastLitTime = time }
        if let since = coveredSince {
            if luma.deviation > 12 || time - since > 8 { coveredSince = nil }
        } else if torch.phase == .off && isFlat && luma.mean < 26 && time - lastLitTime < 0.8 {
            coveredSince = time
            log.write(["type": "covered", "t": .number(time), "how": "sudden"])
        }
        guard torch.phase == .on, time - torch.switchTime > 1.2, isFlat, luma.mean >= 20 else { return }
        torch.forceOff()
        coveredSince = time
        log.write(["type": "covered", "t": .number(time), "how": "torch"])
        let wasUnreliable = !trustMonitor.isReliable
        let previousReason = trustMonitor.reason
        trustMonitor.forceUnreliable(.covered)
        if wasUnreliable && previousReason != .covered { guide.handle(.unreliable(.covered), time: time) }
    }

    private func updateRates(time: Double) {
        guard time - rateWindowStart >= 1 else { return }
        let span = time - rateWindowStart
        framesPerSecond = Double(framesInWindow) / span
        detectionRate = Double(detectionsInWindow) / span
        depthRate = Double(depthsInWindow) / span
        rateWindowStart = time
        framesInWindow = 0
        detectionsInWindow = 0
        depthsInWindow = 0
    }
}
