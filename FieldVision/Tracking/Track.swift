import CoreGraphics
import simd

nonisolated final class Track {
    let id: Int
    let kind: ObjectKind
    var position: SIMD3<Float>
    var velocity = SIMD3<Float>(repeating: 0)
    var confidence: Float = 0
    /// The last 5 detector frames: seen or not.
    var recentHits: [Bool] = []
    var state: TrackState = .maybe
    var wasSure = false
    var lastSeen: Double
    var hiddenTime: Double = 0
    var goneTime: Double = 0
    var box: CGRect
    var isOnGround: Bool
    var hasSaidAhead = false
    var offPathTime: Double = 0
    var hasSaidFast = false
    var isInPath = false
    var isDanger = false
    var aheadDistance: Float = 0
    var lateralOffset: Float = 0
    var distance: Float = 0
    var ghostPosition: SIMD3<Float>
    var yaw: Float = 0
    var totalHits = 0
    /// Floor positions over the last ~1.2 s: speed is measured over this, not frame to frame.
    var history: [(time: Double, position: SIMD2<Float>)] = []
    /// In or near the walking path when last seen: only then is hidden, back or lost worth saying.
    var isRelevant = false
    /// Coming fast towards the walking path right now.
    var isFast = false

    var speed: Float {
        simd_length(SIMD2(velocity.x, velocity.z))
    }

    /// From the oldest to the newest floor position, if they span at least 0.5 s.
    var steadyVelocity: SIMD2<Float>? {
        guard let oldest = history.first, let newest = history.last, newest.time - oldest.time >= 0.5 else { return nil }
        return (newest.position - oldest.position) / Float(newest.time - oldest.time)
    }

    init(id: Int, detection: WorldDetection, time: Double) {
        self.id = id
        kind = detection.kind
        position = detection.position
        ghostPosition = detection.position
        lastSeen = time
        box = detection.box
        isOnGround = detection.isOnGround
    }
}
