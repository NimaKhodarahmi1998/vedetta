import Foundation
import simd

nonisolated extension GuidancePipeline {
    /// What the map draws on top of its splats, in the map's greys: the walking path, the walker, tracked movers
    /// and what blocks the path. Colour is kept for the path, warnings and danger.
    func overlaySplats() -> [SplatVertex] {
        var splats: [SplatVertex] = []
        splats.reserveCapacity(2000)
        let theme = store.theme
        let isReliable = trustMonitor.isReliable
        let forward = SIMD3<Float>(walker.forward.x, 0, walker.forward.y)
        let left = SIMD3<Float>(walker.left.x, 0, walker.left.y)
        let base = SIMD3<Float>(walker.position.x, ground, walker.position.z)
        let isDanger = tracker.tracks.contains { $0.isDanger } || (pathAhead?.isClose ?? false) || isFloorDanger
        let pathColor = !isReliable ? SplatPalette.warn : (isDanger ? SplatPalette.danger : SplatPalette.accent)

        // Walking path: 1.5 m wide, 6 m long, a faint band with brighter edges.
        for ahead in stride(from: Float(0.3), through: 6.3, by: 0.25) {
            for side in stride(from: Float(-0.75), through: 0.751, by: 0.15) {
                let edge: Float = abs(side) > 0.7 ? 1 : 0.3
                let fade = 1 - (ahead / 6.3) * 0.75
                let position = base + forward * ahead + left * side + SIMD3(0, 0.02, 0)
                splats.append(SplatVertex(position: position, color: pathColor, confidence: 0.4 * edge * fade, size: 0.07, mode: .overlay))
            }
        }
        for point in shapes[.person] ?? [] {
            let position = base + forward * point.z + left * point.x + SIMD3(0, point.y, 0)
            splats.append(SplatVertex(position: position, color: theme.tone(0.85), confidence: 0.85, size: 0.09, mode: .overlay))
        }

        for track in tracker.tracks where track.state == .maybe || track.state == .sure || track.state == .hidden {
            appendMover(track, theme: theme, isReliable: isReliable, to: &splats)
        }
        if isReliable, let pathAhead {
            appendPathMarker(pathAhead, theme: theme, base: base, forward: forward, left: left, to: &splats)
        }
        if isReliable {
            appendFloorMarkers(base: base, forward: forward, left: left, to: &splats)
        }
        return splats
    }

    /// Steps and stairs where they are: an edge line at the new level (stairs: a few treads). A low object: a line
    /// across the path at its height. Caution colour, red when it needs action now.
    private func appendFloorMarkers(base: SIMD3<Float>, forward: SIMD3<Float>, left: SIMD3<Float>, to splats: inout [SplatVertex]) {
        for view in stepViews.prefix(3) {
            let feature = view.f
            let color = (feature.kind == .dropOff || stepIsDanger(view)) ? SplatPalette.danger : SplatPalette.warn
            let treads = (feature.kind == .stairsUp || feature.kind == .stairsDown) ? 3 : 1
            let normal = SIMD3<Float>(feature.normal.x, 0, feature.normal.y)
            let direction = SIMD3<Float>(feature.dir.x, 0, feature.dir.y)
            let half = min(2.5, max(0.4, feature.width / 2))
            for tread in 0..<treads {
                let height = ground + feature.level + feature.rise * Float(tread + 1)
                let start = SIMD3<Float>(feature.center.x, height + 0.03, feature.center.y) + normal * (Float(tread) * 0.3)
                for offset in stride(from: -half, through: half + 0.01, by: 0.05) {
                    splats.append(SplatVertex(position: start + direction * offset, color: color, confidence: 0.95, size: 0.09, mode: .overlay))
                }
            }
        }
        guard let floorInfo, floorInfo.kind == .lowObstacle else { return }
        let color = floorInfo.distance < 1.5 ? SplatPalette.danger : SplatPalette.warn
        let center = base + forward * floorInfo.distance + SIMD3(0, floorInfo.height + 0.03, 0)
        for side in stride(from: Float(-0.75), through: 0.76, by: 0.05) {
            splats.append(SplatVertex(position: center + left * side, color: color, confidence: 0.95, size: 0.09, mode: .overlay))
        }
    }

    private func appendMover(_ track: Track, theme: MapTheme, isReliable: Bool, to splats: inout [SplatVertex]) {
        let isHidden = track.state == .hidden
        let position = isHidden ? track.ghostPosition : track.position
        let color: SIMD3<Float> = !isReliable ? theme.tone(0.35)
            : (track.isDanger ? SplatPalette.danger : theme.tone(track.state == .maybe ? 0.4 : 0.6))
        let alpha: Float = !isReliable ? 0.5 : (isHidden ? 0.55 : (track.state == .maybe ? 0.3 + track.confidence * 0.4 : 0.95))
        let jitter: Float = track.state == .maybe ? 0.1 : 0.01
        let cosine = cos(track.yaw)
        let sine = sin(track.yaw)
        let groundPosition = SIMD3<Float>(position.x, ground, position.z)

        for point in shapes[track.kind] ?? [] {
            let shake = SIMD3<Float>(.random(in: -jitter...jitter), .random(in: -jitter...jitter), .random(in: -jitter...jitter))
            let rotated = SIMD3<Float>(point.x * cosine + point.z * sine, point.y, -point.x * sine + point.z * cosine) + shake
            splats.append(SplatVertex(position: groundPosition + rotated, color: color, confidence: alpha, size: 0.09, mode: isHidden ? .ring : .overlay))
        }
        guard track.isFast, let velocity = track.steadyVelocity else { return }
        for step in 0..<16 {
            let seconds = Float(step) * 0.12
            let trailPoint = groundPosition + SIMD3(velocity.x, 0, velocity.y) * seconds + SIMD3(0, 0.3, 0)
            splats.append(SplatVertex(position: trailPoint, color: SplatPalette.danger, confidence: 0.9 - Float(step) * 0.04, size: 0.1, mode: .overlay))
        }
    }

    /// A line across the path for a wall, a ring for an obstacle, and a column where the opening is.
    private func appendPathMarker(_ pathAhead: PathAhead, theme: MapTheme, base: SIMD3<Float>, forward: SIMD3<Float>, left: SIMD3<Float>, to splats: inout [SplatVertex]) {
        let center = base + forward * pathAhead.distance
        let color = pathAhead.isClose ? SplatPalette.danger : theme.tone(0.6)
        if pathAhead.isWall {
            for side in stride(from: Float(-1.0), through: 1.0, by: 0.05) {
                splats.append(SplatVertex(position: center + left * side + SIMD3(0, 0.05, 0), color: color, confidence: 0.9, size: 0.08, mode: .overlay))
            }
        } else {
            for index in 0..<30 {
                let angle = Float(index) / 30 * 2 * .pi
                let ringPoint = center + SIMD3(cos(angle) * 0.4, 0.03, sin(angle) * 0.4)
                splats.append(SplatVertex(position: ringPoint, color: color, confidence: 0.8, size: 0.06, mode: .overlay))
            }
        }
        let side: Float
        switch pathAhead.opening {
            case .none: return
            case .left: side = 1
            case .right: side = -1
        }
        let gap = center + left * (side * 1.1)
        for step in 0..<10 {
            splats.append(SplatVertex(position: gap + SIMD3(0, 0.05 + Float(step) * 0.18, 0), color: SplatPalette.accent, confidence: 0.9, size: 0.1, mode: .overlay))
        }
    }
}
