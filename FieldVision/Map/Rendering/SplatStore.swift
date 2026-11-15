import Foundation
import QuartzCore
import simd

nonisolated final class SplatStore: @unchecked Sendable {
    private let lock = NSLock()
    private var mapVertices: [SplatVertex] = []
    private var mapVersion = 0
    private var overlayVertices: [SplatVertex] = []
    private var walker = SIMD3<Float>(0, 0, 0)
    private var forward = SIMD2<Float>(0, -1)
    private var ground: Float = -1.35
    private var isReliable = true
    private var waveStartTime = -99.0
    private var currentTheme = MapTheme.light

    var theme: MapTheme {
        lock.withLock { currentTheme }
    }

    func setMap(_ vertices: [SplatVertex]) {
        lock.withLock {
            mapVertices = vertices
            mapVersion += 1
        }
    }

    func setOverlay(_ vertices: [SplatVertex], walker: SIMD3<Float>, forward: SIMD2<Float>, ground: Float, isReliable: Bool) {
        lock.withLock {
            overlayVertices = vertices
            self.walker = walker
            self.forward = forward
            self.ground = ground
            self.isReliable = isReliable
        }
    }

    func setTheme(_ theme: MapTheme) {
        lock.withLock {
            currentTheme = theme
        }
    }

    func sendWave() {
        lock.withLock {
            waveStartTime = CACurrentMediaTime()
        }
    }

    func snapshot(knownVersion: Int) -> SplatSnapshot {
        lock.withLock {
            SplatSnapshot(
                mapVertices: knownVersion == mapVersion ? [] : mapVertices,
                mapVersion: mapVersion,
                overlayVertices: overlayVertices,
                walker: walker,
                forward: forward,
                ground: ground,
                isReliable: isReliable,
                waveStartTime: waveStartTime,
                theme: currentTheme
            )
        }
    }
}
