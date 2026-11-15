import ARKit

nonisolated extension GuidancePipeline {
    var isGroundKnown: Bool { planeGround != nil || pointGround != nil }
    var ground: Float { planeGround ?? pointGround ?? (walker.position.y - 1.35) }

    func updatePlanes(_ anchors: [ARAnchor]) {
        for case let plane as ARPlaneAnchor in anchors {
            switch plane.alignment {
                case .horizontal: considerFloor(plane)
                case .vertical: addWallPlane(plane)
                @unknown default: break
            }
        }
    }

    /// The floor is the horizontal plane closest to chest height minus 1.35 m.
    private func considerFloor(_ plane: ARPlaneAnchor) {
        let height = plane.transform.columns.3.y
        let drop = walker.position.y - height
        guard drop > 0.5 && drop < 2.2 else { return }
        if let planeGround, abs(drop - 1.35) >= abs((walker.position.y - planeGround) - 1.35) { return }
        planeGround = height
    }

    /// A grid of splats on a wall plane, so walls show in the map and count as solid.
    private func addWallPlane(_ plane: ARPlaneAnchor) {
        let width = plane.planeExtent.width
        let height = plane.planeExtent.height
        guard width > 0.3, height > 0.3 else { return }
        let step: Float = 0.15
        var points: [SIMD3<Float>] = []
        var x = -width / 2
        while x <= width / 2 {
            var z = -height / 2
            while z <= height / 2 {
                let world = plane.transform * SIMD4<Float>(plane.center.x + x, 0, plane.center.z + z, 1)
                points.append(SIMD3(world.x, world.y, world.z))
                z += step
            }
            x += step
        }
        let wallColor = SIMD3<Float>(0.62, 0.66, 0.80)
        map.add(points, colors: Array(repeating: wallColor, count: points.count), time: frameTime)
    }

    /// Fallback floor: the lowest dense layer of map points within 3 m.
    func estimateGroundFromPoints() {
        let center = walker.position
        var heights: [Float] = []
        for cell in map.cells.values where cell.hits >= 2 {
            let dx = cell.position.x - center.x
            let dz = cell.position.z - center.z
            if dx * dx + dz * dz < 9 && cell.position.y < center.y - 0.5 { heights.append(cell.position.y) }
        }
        guard heights.count >= 30 else { return }
        heights.sort()
        pointGround = heights[heights.count / 10]
    }
}
