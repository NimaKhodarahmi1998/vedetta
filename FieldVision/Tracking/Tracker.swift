import Foundation
import simd

/// Keeps identities through short occlusions and decides what is worth saying.
nonisolated final class Tracker {
    /// Seconds a hidden object is remembered.
    static let memoryDuration: Double = 3.0

    private(set) var tracks: [Track] = []
    var onEvent: ((GuideEvent) -> Void)?
    /// Each person's number at every change (sure, hidden, back, lost, out), for measuring later.
    var log: EventLog?

    private var nextId = 1
    private var lastCrowdTime = -99.0

    func reset() {
        tracks.removeAll()
        nextId = 1
    }

    func update(with detections: [WorldDetection], time: Double, walker: Walker) {
        var candidates: [(distance: Float, trackIndex: Int, detectionIndex: Int)] = []
        for (trackIndex, track) in tracks.enumerated() where track.state != .lost && track.state != .out {
            let elapsed = Float(max(0, time - track.lastSeen))
            let predicted = Self.predictedPosition(of: track, after: time - track.lastSeen)
            let gate = max(1.0, track.speed * elapsed + 0.9)
            for (detectionIndex, detection) in detections.enumerated()
            where detection.kind.matchGroup == track.kind.matchGroup {
                let distance = simd_distance(
                    SIMD2(predicted.x, predicted.z),
                    SIMD2(detection.position.x, detection.position.z)
                )
                if distance < gate { candidates.append((distance, trackIndex, detectionIndex)) }
            }
        }
        candidates.sort { $0.distance < $1.distance }

        var matchedTracks = Set<Int>()
        var matchedDetections = Set<Int>()
        for (_, trackIndex, detectionIndex) in candidates
        where !matchedTracks.contains(trackIndex) && !matchedDetections.contains(detectionIndex) {
            matchedTracks.insert(trackIndex)
            matchedDetections.insert(detectionIndex)
            apply(detections[detectionIndex], to: tracks[trackIndex], time: time, walker: walker)
        }
        for (trackIndex, track) in tracks.enumerated() where !matchedTracks.contains(trackIndex) {
            record(isHit: false, for: track)
        }
        for (detectionIndex, detection) in detections.enumerated() where !matchedDetections.contains(detectionIndex) {
            let track = Track(id: nextId, detection: detection, time: time)
            nextId += 1
            let distance = simd_distance(
                SIMD2(detection.position.x, detection.position.z),
                SIMD2(walker.position.x, walker.position.z)
            )
            track.confidence = detection.confidence * confidenceGain(atDistance: distance)
            record(isHit: true, for: track)
            tracks.append(track)
        }
    }

    /// Runs on every camera frame.
    func tick(time: Double, delta: Double, walker: Walker, camera: CameraSnapshot, isReliable: Bool) {
        for track in tracks {
            updateGeometry(of: track, walker: walker)
            track.isDanger = false
            if isReliable {
                updateVisibility(of: track, time: time, delta: delta, walker: walker, camera: camera)
            }
        }
        guard isReliable else { return }

        let nearbyPeople = tracks.filter {
            $0.kind == .person && $0.state == .sure && $0.distance < 5 && $0.aheadDistance > 0
        }
        let isCrowded = nearbyPeople.count >= 5
        if isCrowded && time - lastCrowdTime > 20 {
            lastCrowdTime = time
            onEvent?(.crowd)
        }

        for track in tracks {
            updatePath(of: track, time: time, delta: delta, walker: walker, isCrowded: isCrowded)
        }

        tracks.removeAll {
            ($0.state == .lost && $0.goneTime > 1.0) || ($0.state == .out && $0.goneTime > 2.0) || time - $0.lastSeen > 8
        }
    }

    /// Where a track not seen for `elapsed` seconds probably is. It goes on but slows down, as people do behind an
    /// obstacle, so the ghost stays near where it went out of sight (at most half a second of walking) instead of
    /// drifting out of view and coming back with a new number.
    static func predictedPosition(of track: Track, after elapsed: Double) -> SIMD3<Float> {
        let fade: Float = 0.5
        let seconds = Float(max(0, min(elapsed, memoryDuration)))
        return track.position + track.velocity * (fade * (1 - exp(-seconds / fade)))
    }

    private func logTrack(_ track: Track, _ change: String, time: Double) {
        log?.write([
            "type": "track", "t": .number(time), "id": .integer(track.id), "kind": .text("\(track.kind)"),
            "change": .text(change), "ahead": .number(Double(track.aheadDistance)),
            "side": .number(Double(track.lateralOffset)), "relevant": .flag(track.isRelevant)
        ])
    }

    private func confidenceGain(atDistance distance: Float) -> Float {
        0.18 + 0.4 * exp(-distance / 6)
    }

    private func record(isHit: Bool, for track: Track) {
        track.recentHits.append(isHit)
        if track.recentHits.count > 5 { track.recentHits.removeFirst(track.recentHits.count - 5) }
    }

    private func apply(_ detection: WorldDetection, to track: Track, time: Double, walker: Walker) {
        let elapsed = Float(max(0.03, time - track.lastSeen))
        let newPosition = track.position + (detection.position - track.position) * 0.6
        var velocity = (newPosition - track.position) / elapsed
        velocity.y = 0
        // A jump, not a movement.
        if simd_length(velocity) > 15 { velocity = .zero }
        track.velocity = track.velocity * 0.6 + velocity * 0.4
        track.position = newPosition
        track.lastSeen = time
        track.box = detection.box
        track.isOnGround = detection.isOnGround
        track.goneTime = 0
        let distance = simd_distance(SIMD2(newPosition.x, newPosition.z), SIMD2(walker.position.x, walker.position.z))
        track.confidence = min(1, track.confidence + detection.confidence * confidenceGain(atDistance: distance))
        record(isHit: true, for: track)
        track.totalHits += 1
        if detection.isOnGround {
            track.history.append((time, SIMD2(newPosition.x, newPosition.z)))
            while let oldest = track.history.first, time - oldest.time > 1.2 { track.history.removeFirst() }
        } else {
            // An estimated distance jumps around: never used for speed.
            track.history.removeAll()
        }
        if track.speed > 0.3 { track.yaw = atan2(track.velocity.x, track.velocity.z) }
    }

    private func updateGeometry(of track: Track, walker: Walker) {
        let offset = SIMD2(track.position.x - walker.position.x, track.position.z - walker.position.z)
        track.distance = simd_length(offset)
        track.aheadDistance = simd_dot(offset, walker.forward)
        track.lateralOffset = simd_dot(offset, walker.left)
    }

    private func updateVisibility(of track: Track, time: Double, delta: Double, walker: Walker, camera: CameraSnapshot) {
        let timeSinceSeen = time - track.lastSeen
        if timeSinceSeen < 0.4 {
            let hitCount = track.recentHits.filter { $0 }.count
            let isConfirmed = track.confidence >= 0.6 && hitCount >= 3
            let nextState: TrackState = isConfirmed ? .sure : (track.state == .sure ? .sure : .maybe)
            if track.state == .hidden {
                track.state = nextState
                if track.wasSure { logTrack(track, "back", time: time) }
                if track.wasSure && track.isRelevant && track.kind.isMover {
                    onEvent?(.back(track.kind, isLeft: track.lateralOffset > 0))
                }
            } else if track.state != .lost {
                track.state = nextState
            }
            if track.state == .sure && !track.wasSure {
                track.wasSure = true
                logTrack(track, "sure", time: time)
            }
            track.hiddenTime = 0
            track.ghostPosition = track.position
            track.isRelevant = track.aheadDistance > 0 && track.aheadDistance < 8 && abs(track.lateralOffset) < 1.5
            return
        }

        let predicted = Self.predictedPosition(of: track, after: timeSinceSeen)
        let canHide = (track.state == .sure || track.state == .hidden) && track.kind.isMover
            && camera.isInView(predicted) && simd_distance(predicted, walker.position) < 25
        if canHide {
            if track.state != .hidden {
                track.state = .hidden
                track.hiddenTime = 0
                if track.wasSure { logTrack(track, "hidden", time: time) }
                if track.wasSure && track.isRelevant {
                    onEvent?(.hidden(track.kind, isLeft: track.lateralOffset > 0))
                }
            }
            track.hiddenTime += delta
            track.ghostPosition = predicted
            if track.hiddenTime > Self.memoryDuration {
                track.state = .lost
                if track.wasSure { logTrack(track, "lost", time: time) }
                if track.wasSure && track.isRelevant { onEvent?(.lost(track.kind)) }
            }
        } else if track.state == .sure || track.state == .maybe || track.state == .hidden {
            // Left the picture: not an occlusion.
            if track.wasSure { logTrack(track, "out", time: time) }
            track.state = .out
        }
        track.goneTime += delta
    }

    private func updatePath(of track: Track, time: Double, delta: Double, walker: Walker, isCrowded: Bool) {
        guard track.state == .sure else {
            track.isInPath = false
            track.isFast = false
            return
        }
        let halfWidth: Float = track.kind == .thing ? 0.7 : 0.95
        let isInPath = track.aheadDistance > 0.3 && track.aheadDistance < 6 && abs(track.lateralOffset) < halfWidth
        let isFast = isComingFast(track, time: time, walker: walker)
        if isFast && !track.hasSaidFast {
            track.hasSaidFast = true
            onEvent?(.fast(track.kind, isLeft: track.lateralOffset > 0))
        }
        if isInPath {
            track.offPathTime = 0
            if !track.hasSaidAhead && !isFast && (!isCrowded || track.aheadDistance < 2) {
                track.hasSaidAhead = true
                onEvent?(.ahead(track.kind, isClose: track.aheadDistance < 2.5))
            }
        } else {
            track.offPathTime += delta
            if track.offPathTime > 4 { track.hasSaidAhead = false }
        }
        track.isInPath = isInPath
        track.isFast = isFast
        track.isDanger = isFast || (isInPath && track.aheadDistance < 3.5)
    }

    /// Needs real floor positions, enough sightings and a steady speed over half a second,
    /// so a person sitting still whose estimated distance jumps is never fast.
    private func isComingFast(_ track: Track, time: Double, walker: Walker) -> Bool {
        guard track.kind.isMover, track.isOnGround, track.totalHits >= 5, track.distance < 10,
              time - track.lastSeen < 0.4,
              let velocity = track.steadyVelocity, simd_length(velocity) > 2.5, simd_length(velocity) < 12 else {
            return false
        }
        let aheadSpeed = simd_dot(velocity, walker.forward)
        let lateralSpeed = simd_dot(velocity, walker.left)
        for step in 0...10 {
            let t = Float(step) * 0.25
            let lateral = track.lateralOffset + lateralSpeed * t
            let ahead = track.aheadDistance + aheadSpeed * t
            if abs(lateral) < 0.9 && ahead > 0 && ahead < 8 { return true }
        }
        return false
    }
}
