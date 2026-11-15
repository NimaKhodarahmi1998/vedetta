import ARKit
import simd

nonisolated extension GuidancePipeline {
    /// Finds what blocks the walking path in the 3D map: a wall, an obstacle, and an opening in a wall.
    func analyzePathAhead(time: Double) {
        guard trustMonitor.isReliable, isGroundKnown else {
            pathAhead = nil
            return
        }
        let floorHeight = ground
        let reach: Float = torch.isOn ? Self.nearRange : 5
        let movers = tracker.tracks
            // Only people seen right now are cut out of the map: a hidden one's last place is the board they're behind.
            .filter { $0.kind.isMover && ($0.state == .sure || $0.state == .maybe) }
            .map { SIMD2($0.position.x, $0.position.z) }

        var corridor: [Float] = []
        var nearBand: [(lateral: Float, ahead: Float)] = []
        // Every point in the walking corridor from 5 cm up, for telling stairs going up from a wall.
        var profile: [(ahead: Float, height: Float)] = []
        for cell in map.cells.values where cell.hits >= 2 && time - cell.lastSeen < 1.5 {
            let height = cell.position.y - floorHeight
            guard height >= 0.05, height <= 2.0 else { continue }
            let offset = SIMD2(cell.position.x - walker.position.x, cell.position.z - walker.position.z)
            let ahead = simd_dot(offset, walker.forward)
            guard ahead >= 0.3, ahead <= reach + 1 else { continue }
            let lateral = simd_dot(offset, walker.left)
            guard abs(lateral) <= 2.2 else { continue }
            let flatPosition = SIMD2(cell.position.x, cell.position.z)
            guard !movers.contains(where: { simd_distance($0, flatPosition) < 0.7 }) else { continue }
            // A narrow strip straight ahead, so a staircase's side walls and railings stay out of it.
            if abs(lateral) < 0.3 { profile.append((ahead, height)) }
            guard height >= 0.3 else { continue }
            nearBand.append((lateral, ahead))
            if abs(lateral) < 0.55 && ahead <= reach { corridor.append(ahead) }
        }

        guard corridor.count >= 6 else {
            pathAhead = nil
            pathClearTime += 0.2
            if pathClearTime > 4 {
                hasSaidAhead = false
                hasSaidWall = false
                saidOpening = .none
                hasSaidNearWall = false
            }
            return
        }
        corridor.sort()
        // Near, but not the single closest point, which is often noise.
        let distance = corridor[corridor.count / 7]
        // Stairs going up rise above 30 cm a few treads in: that's the staircase, not an obstacle or a wall.
        if let stretch = steps.risingStretch(walker: walker.position, fwd: walker.forward),
           distance >= stretch.from && distance <= stretch.to {
            pathAhead = nil
            return
        }
        // The same read straight from the map, for when the floor reader missed them: the lowest points of the
        // corridor climbing steadily ahead are treads, not a wall.
        let rising = isGoingDownAhead(at: time) ? nil : risingProfile(profile, from: max(0.3, distance - 0.6))
        stairsProfileHits = rising == nil ? 0 : stairsProfileHits + 1
        if let stairs = rising {
            pathAhead = nil
            // Said once it holds for two checks in a row.
            if stairsProfileHits >= 2 && time - lastStairsUpLineTime > 10 {
                lastStairsUpLineTime = time
                log.write(["type": "stairsProfile", "t": .number(time), "d": .number(Double(stairs))])
                guide.handle(.floor(.stairsUp, distance: stairs), time: time, key: "stairs-up")
            }
            return
        }

        // A wall is solid across about 2 m at the same distance; an opening is a gap of 0.8 m or more in it.
        var isSolid = [Bool](repeating: false, count: 44)
        for point in nearBand where abs(point.ahead - distance) < 0.5 {
            let bin = Int((point.lateral + 2.2) / 0.1)
            if isSolid.indices.contains(bin) { isSolid[bin] = true }
        }
        // Judged over the part of those 2 m the camera can actually see: half a metre away it sees only about ±25 cm.
        let halfWidth = min(1.0, max(0.2, distance * viewHalfWidthPerMetre))
        let central = isSolid[Int(((2.2 - halfWidth) / 0.1).rounded())..<Int(((2.2 + halfWidth) / 0.1).rounded())]
        let coverage = Float(central.filter { $0 }.count) / Float(max(1, central.count))
        let isWall = coverage >= 0.6
        if isWall { lastWallSeen = (distance, time) }
        // An opening only where the camera can see, and not this close: half a metre from a wall it sees too little
        // of it to know where the way through is.
        let opening = isWall && distance >= 1.5
            ? widestOpening(in: isSolid, visibleHalfWidth: distance * viewHalfWidthPerMetre) : .none

        pathAhead = PathAhead(distance: distance, isWall: isWall, opening: opening)
        pathClearTime = 0

        // On or near stairs, walls and obstacles keep quiet (the beeps go on): the stairs line matters more, and a
        // staircase's own walls and railings would otherwise be called «Muro davanti».
        let isQuiet = isStairsContext(at: time)
        if !isQuiet && (!hasSaidAhead || (isWall && !hasSaidWall) || (opening != .none && opening != saidOpening)) {
            hasSaidAhead = true
            hasSaidWall = isWall
            saidOpening = opening
            guide.handle(isWall ? .wall(isClose: distance < 1.2, opening: opening) : .obstacle, time: time)
            if isWall && distance < 1.2 { hasSaidNearWall = true }
        } else if !isQuiet && isWall && distance < 1.0 && !hasSaidNearWall {
            // Said again, once, when it is close: the first «Muro davanti» may have come from metres away.
            hasSaidNearWall = true
            guide.handle(.wall(isClose: true, opening: .none), time: time)
        }

        let beepDistance: Float = isWall ? 2.0 : 4.5
        guard distance < beepDistance else { return }
        let interval = max(0.12, 0.12 + Double((distance - 0.8) / max(0.5, beepDistance - 0.8)) * 0.7)
        if time - lastProximityTime >= interval {
            lastProximityTime = time
            guide.handle(.proximity, time: time)
        }
    }

    /// Stairs going up, seen from below: the lowest points in each 25 cm slice of the corridor climb steadily, about
    /// 15–20 cm per tread. A wall stands at one distance instead, with points from the floor up. Returns where the
    /// climb starts. When Apple's classifier also sees stairs, a smaller climb is enough.
    func risingProfile(_ profile: [(ahead: Float, height: Float)], from start: Float) -> Float? {
        let size: Float = 0.25
        var slices = [[Float]](repeating: [], count: 10)
        for point in profile where point.ahead >= start {
            let index = Int((point.ahead - start) / size)
            if index < slices.count { slices[index].append(point.height) }
        }
        var low: [(index: Int, height: Float)] = []
        var flat = 0
        for (index, heights) in slices.enumerated() where heights.count >= 3 {
            let sorted = heights.sorted()
            let tread = sorted[sorted.count / 5]
            low.append((index, tread))
            // A tread is flat: most of its points sit within a riser's height of its surface. A chair, a desk or a
            // monitor spread from their legs to their tops.
            if sorted[sorted.count / 2] - tread <= 0.12 { flat += 1 }
        }
        guard low.count >= 4, let first = low.first, let last = low.last,
              last.index - first.index >= 3, Float(flat) >= 0.75 * Float(low.count) else { return nil }
        var climbs = 0
        for (previous, next) in zip(low, low.dropFirst()) {
            let step = next.height - previous.height
            // Climbs in even steps: never back down, never more than a tall riser per slice.
            if step < -0.08 || step > 0.3 * Float(next.index - previous.index) { return nil }
            if step >= 0.06 { climbs += 1 }
        }
        let rise = last.height - first.height
        let slope = rise / (Float(last.index - first.index) * size)
        // Stairs start from the floor and climb more than once: a table top starts high, a box climbs once.
        guard first.height <= 0.25, climbs >= 2, rise >= 0.3, slope >= 0.4, slope <= 1.0 else { return nil }
        return start + Float(first.index) * size
    }

    /// How wide the camera sees per metre ahead, half of it, with the phone upright (from the lens's own numbers).
    var viewHalfWidthPerMetre: Float {
        guard let camera = lastCamera, camera.intrinsics[1][1] > 0 else { return 0.42 }
        return Float(camera.resolution.height) / 2 / camera.intrinsics[1][1]
    }

    /// The nearest wall straight ahead among ARKit's own vertical planes, measured flat.
    func wallDistanceFromPlanes() -> Float? {
        guard let camera = lastCamera else { return nil }
        let forward = SIMD3<Float>(walker.forward.x, 0, walker.forward.y)
        let query = ARRaycastQuery(origin: camera.position, direction: forward, allowing: .existingPlaneGeometry, alignment: .vertical)
        guard let hit = session.raycast(query).first else { return nil }
        let column = hit.worldTransform.columns.3
        return simd_distance(SIMD2(column.x, column.z), SIMD2(camera.position.x, camera.position.z))
    }

    /// A wall within a metre: from ARKit's vertical planes, or, when a plain wall fills the picture and guidance has
    /// gone unreliable, from the wall seen in the map a moment before. Said once as «Muro davanti, vicino», with
    /// faster beeps, until the walker steps back. Runs even while guidance is unreliable.
    func checkNearWall(time: Double) {
        guard !isStairsContext(at: time) else { return }
        var near = wallDistanceFromPlanes()
        if near == nil, !trustMonitor.isReliable, trustMonitor.reason == .features,
           let last = lastWallSeen, time - last.time < 2, last.distance < 1.5 {
            near = last.distance
        }
        guard let distance = near, distance < 1.2 else {
            let planeIsFar = near.map { $0 > 1.6 } ?? true
            let mapIsFar = pathAhead.map { !$0.isWall || $0.distance > 1.6 } ?? true
            if planeIsFar && mapIsFar { hasSaidNearWall = false }
            return
        }
        if !hasSaidNearWall {
            hasSaidNearWall = true
            guide.handle(.wall(isClose: true, opening: .none), time: time)
        }
        let interval = max(0.12, 0.12 + Double((distance - 0.5) / 0.7) * 0.5)
        if time - lastProximityTime >= interval {
            lastProximityTime = time
            guide.handle(.proximity, time: time)
        }
    }

    /// On or near stairs: stairs going up said in the last 6 s, a way down warned of in the last 8 s, or the floor
    /// reader's rising stretch ahead.
    func isStairsContext(at time: Double) -> Bool {
        time - lastStairsUpLineTime < 6 || time - lastDownWarningTime < 8
            || steps.risingStretch(walker: walker.position, fwd: walker.forward) != nil
    }

    /// The widest gap of 0.8 m or more in the wall, among the bins the camera can see: an unseen bin is not open.
    private func widestOpening(in isSolid: [Bool], visibleHalfWidth: Float) -> PathOpening {
        var bestLength = 0
        var bestMiddle = 0
        var run = 0
        for bin in isSolid.indices {
            let lateral = (Float(bin) + 0.5) * 0.1 - 2.2
            run = isSolid[bin] || abs(lateral) > visibleHalfWidth ? 0 : run + 1
            if run > bestLength {
                bestLength = run
                bestMiddle = bin - run / 2
            }
        }
        guard bestLength >= 8 else { return .none }
        let middle = (Float(bestMiddle) + 0.5) * 0.1 - 2.2
        guard abs(middle) > 0.45 else { return .none }
        return middle > 0 ? .left : .right
    }
}
