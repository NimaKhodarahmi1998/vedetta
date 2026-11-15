import ARKit
import simd

nonisolated extension GuidancePipeline {
    func requestDetections(in pixelBuffer: CVPixelBuffer, prepare: (@Sendable (CVPixelBuffer) -> CVPixelBuffer?)?,
                           camera: CameraSnapshot, time: Double) {
        isDetectorBusy = true
        lastDetectionTime = time
        nonisolated(unsafe) let picture = pixelBuffer
        detector.detect(pixelBuffer, prepare: prepare) { [weak self] detections, milliseconds in
            guard let self else { return }
            queue.async {
                self.handleDetections(detections, milliseconds: milliseconds, picture: picture, camera: camera, time: time)
            }
        }
    }

    private func handleDetections(_ detections: [ImageDetection], milliseconds: Double, picture: CVPixelBuffer,
                                  camera: CameraSnapshot, time: Double) {
        isDetectorBusy = false
        detectionMilliseconds = milliseconds
        detectionsInWindow += 1
        guard trustMonitor.isReliable else { return }
        let walkerPosition = SIMD2(walker.position.x, walker.position.z)
        // With the torch on, what it lights is trusted (5 m); beyond that, a clear detection that is itself lit
        // (a street lamp, a shop window) still counts, up to the normal range.
        var litFar = Set<Int>()
        if torch.isOn {
            let sampler = LitSampler(picture)
            for (index, detection) in detections.enumerated() where detection.confidence >= 0.5
                && sampler.boxLuma(detection.box, sensorW: Float(camera.resolution.width), sensorH: Float(camera.resolution.height)) >= 2 * LitSampler.litLuma {
                litFar.insert(index)
            }
            sampler.close()
        }
        var placed: [WorldDetection] = []
        for (index, detection) in detections.enumerated() {
            guard let world = place(detection, camera: camera) else { continue }
            let distance = simd_distance(SIMD2(world.position.x, world.position.z), walkerPosition)
            if world.kind == .person, detection.box.minY < 0.04,
               let rule = ownBodyRule(world, box: detection.box, distance: distance, camera: camera) {
                if time - lastSelfLogTime > 0.5 {
                    lastSelfLogTime = time
                    log.write(["type": "self", "t": .number(time), "rule": .text(rule), "d": .number(Double(distance))])
                }
                continue
            }
            let limit = torch.isOn && !litFar.contains(index) ? Self.nearRange : Self.maxRange
            if distance <= limit { placed.append(world) }
        }
        tracker.update(with: placed, time: time, walker: walker)
    }

    /// The walker's own legs and feet, seen when the phone points down, are not another person. Only for "person"
    /// boxes touching the bottom of the picture (`box` is Vision's: upright, bottom-left origin): nobody else can
    /// stand inside the walker's own footprint; a box placed below the floor or right at the camera is impossible;
    /// and with the phone pointing well down, a box that stays in the lower half of the picture has no room for a head.
    private func ownBodyRule(_ world: WorldDetection, box: CGRect, distance: Float, camera: CameraSnapshot) -> String? {
        if world.isOnGround && distance < 0.7 { return "footprint" }
        if !world.isOnGround && ((isGroundKnown && world.position.y < ground - 0.3)
            || simd_distance(world.position, camera.position) < 0.6) {
            return "impossible"
        }
        let look = -SIMD3<Float>(camera.transform.columns.2.x, camera.transform.columns.2.y, camera.transform.columns.2.z)
        let pitchDown = asin(max(-1, min(1, -look.y)))
        if pitchDown > 0.6 && box.maxY < 0.55 { return "headless" }
        return nil
    }

    /// Puts a detection in the world with a ray from the camera through its feet to the floor.
    /// The floor plane is extended without limit, so far feet still get real metres; without a floor hit,
    /// the distance comes from the box height.
    private func place(_ detection: ImageDetection, camera: CameraSnapshot) -> WorldDetection? {
        guard let kind = ObjectKind(detectorLabel: detection.label) else { return nil }
        let box = detection.box
        // Vision's picture is upright with a bottom-left origin: sensor x is upright y, sensor y is 1 minus upright x.
        let feetX = Float(box.midX)
        let feetY = Float(1 - box.minY)
        let sensorWidth = Float(camera.resolution.width)
        let sensorHeight = Float(camera.resolution.height)
        let origin = camera.position
        let direction = camera.rayDirection(x: feetY * sensorWidth, y: (1 - feetX) * sensorHeight)

        var position = floorHit(from: origin, direction: direction)
        let isOnGround = position != nil
        if position == nil {
            let boxHeight = Float(box.height) * sensorWidth
            if boxHeight > 4 { position = origin + direction * (camera.intrinsics[0][0] * kind.typicalHeight / boxHeight) }
        }
        guard let position else { return nil }
        let uprightBox = CGRect(x: 1 - box.maxY, y: 1 - box.maxX, width: box.height, height: box.width)
        return WorldDetection(kind: kind, confidence: detection.confidence, position: position, box: uprightBox, isOnGround: isOnGround)
    }

    private func floorHit(from origin: SIMD3<Float>, direction: SIMD3<Float>) -> SIMD3<Float>? {
        let floorHeight = ground
        for target in [ARRaycastQuery.Target.existingPlaneInfinite, .estimatedPlane] {
            let query = ARRaycastQuery(origin: origin, direction: direction, allowing: target, alignment: .horizontal)
            for hit in session.raycast(query) {
                let column = hit.worldTransform.columns.3
                let candidate = SIMD3<Float>(column.x, column.y, column.z)
                let isFloor = isGroundKnown ? abs(candidate.y - floorHeight) < 0.25 : origin.y - candidate.y > 0.5
                if isFloor && simd_distance(candidate, origin) < 30 { return candidate }
            }
        }
        return nil
    }
}
