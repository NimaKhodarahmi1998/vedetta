import CoreVideo
import simd

/// A low object close by in the walking path, read from the 3D map.
/// Steps, stairs and drops come from the floor reader (FloorSteps.swift), which sees out to 30 m and remembers them.
nonisolated struct FloorInfo {
    var kind: FloorKind
    var distance: Float
    /// For a low object, its height above the floor (metres).
    var height: Float
}

nonisolated extension GuidancePipeline {
    // MARK: steps and stairs (FloorSteps.swift)

    func stepCamera(_ camera: CameraSnapshot) -> StepCam {
        StepCam(transform: camera.transform, intrinsics: camera.intrinsics,
                width: Float(camera.resolution.width), height: Float(camera.resolution.height))
    }

    /// The floor reader's own band of the picture, from just above the horizon down (4 times a second).
    func requestFloorDepth(in pixelBuffer: CVPixelBuffer, camera: CameraSnapshot, featurePoints: [SIMD3<Float>],
                           band: DepthBand, gain: Float, time: Double) {
        isDepthBusy = true
        lastFloorDepthTime = time
        nonisolated(unsafe) let picture = pixelBuffer
        let lowLight = self.lowLight
        depthEstimator.estimate(prepared: {
            lowLight.band(picture, band: band, gain: gain, w: DepthEstimator.modelWidth, h: DepthEstimator.modelHeight)
        }) { [weak self] relativeDepth, _ in
            guard let self else { return }
            queue.async {
                self.handleFloorDepth(relativeDepth, band: band, picture: picture, camera: camera, featurePoints: featurePoints, time: time)
            }
        }
    }

    /// Metric scale from this frame's feature points (or, with too few, from the known floor right in front), then read.
    private func handleFloorDepth(_ relativeDepth: [Float]?, band: DepthBand, picture: CVPixelBuffer, camera: CameraSnapshot,
                                  featurePoints: [SIMD3<Float>], time: Double) {
        isDepthBusy = false
        guard let relativeDepth else { return }
        let cam = stepCamera(camera)
        let width = DepthEstimator.modelWidth
        let height = DepthEstimator.modelHeight
        var pairs = DepthPairs.fromPoints(featurePoints, rel: relativeDepth, W: width, H: height, band: band, cam: cam)
        if pairs.count < 8 && isGroundKnown {
            pairs += DepthPairs.fromFloor(rel: relativeDepth, W: width, H: height, band: band, cam: cam, ground: ground)
        }
        floorScale.fit(pairs.map { (relative: $0.rel, depth: $0.z) }, time: time)
        feedSteps(relativeDepth, band: band, scale: floorScale, picture: picture, camera: camera, time: time)
    }

    /// One depth picture into the floor reader, only with a scale fitted on this very picture.
    /// In dim light or with the torch on, only spots that are lit count.
    func feedSteps(_ relativeDepth: [Float], band: DepthBand, scale: DepthScale, picture: CVPixelBuffer,
                   camera: CameraSnapshot, time: Double) {
        guard isGroundKnown, trustMonitor.isReliable, scale.isValid, scale.fittedAt >= time - 1e-6 else { return }
        let grid = DepthGrid(rel: relativeDepth, W: DepthEstimator.modelWidth, H: DepthEstimator.modelHeight,
                             band: band, s: scale.slope, t: scale.intercept)
        let cam = stepCamera(camera)
        if lowLight.active || torch.isOn {
            let sampler = LitSampler(picture)
            defer { sampler.close() }
            _ = steps.ingest(grid, cam: cam, ground: ground, t: time, lit: { sampler.lit($0) })
        } else {
            _ = steps.ingest(grid, cam: cam, ground: ground, t: time)
        }
    }

    /// What the walker should hear about steps and stairs, and what the map shows (up to 3, within 30 m and 70 degrees).
    func analyzeSteps(time: Double) {
        guard trustMonitor.isReliable, isGroundKnown else {
            stepViews = []
            return
        }
        steps.maintain(t: time, walker: walker.position, fwd: walker.forward)
        let views = steps.views(walker: walker.position, fwd: walker.forward)
        stepViews = views
            .filter { !$0.onIt && $0.dist <= StepReader.maxRange && (abs($0.bearing) <= StepReader.halfFOV || $0.sayDistance < 3) }
            .sorted { ($0.inPath ? 0 : 1, $0.sayDistance) < ($1.inPath ? 0 : 1, $1.sayDistance) }
        guard let line = stepSay.next(views, t: time) else { return }
        let isUp = line.kind == .stepUp || line.kind == .stairsUp
        // Never «in salita» while points lie well below the floor ahead: calling a way down a way up is the one
        // mistake that must not happen. The floor-end check speaks for that case.
        // Steps up only close by, and only when the 3D map sees a real step there too: far away, or without that
        // check, furniture and boxes climb like stairs.
        let vetoed = isUp && (isGoingDownAhead(at: time) || line.far || !isStepUpConfirmed(near: line.distance, time: time))
        log.write([
            "type": "stepLine", "t": .number(time), "kind": .text("\(line.kind)"), "d": .number(Double(line.distance)),
            "far": .flag(line.far), "vetoed": .flag(vetoed)
        ])
        if vetoed { return }
        if (line.kind == .stepDown || line.kind == .stairsDown || line.kind == .dropOff) && line.distance < 4 {
            lastDownWarningTime = time
        }
        if line.far {
            guide.handle(.floorFar(line.kind, distance: line.distance, side: line.side, isUrgent: line.urgent), time: time, maxWait: 6)
        } else {
            guide.handle(.floor(line.kind, distance: line.distance), time: time)
        }
    }

    func stepIsDanger(_ view: StepView) -> Bool {
        guard let along = view.along else { return false }
        switch view.f.kind {
            case .dropOff, .stairsDown: return along < 4
            default: return along < 1.0
        }
    }

    /// A drop or stairs going down ahead (under 4 m), a step right in front, or a low object close by.
    var isFloorDanger: Bool {
        if let floorInfo {
            switch floorInfo.kind {
                case .dropOff, .stairsDown: return true
                case .lowObstacle: if floorInfo.distance < 1.5 { return true }
                default: if floorInfo.distance < 1.0 { return true }
            }
        }
        return stepViews.contains { stepIsDanger($0) }
    }

    // MARK: low objects in the walking path (read from the 3D map like a cane)

    /// Slices the corridor into 20 cm bands to 3.7 m and reads the floor height in each; something clearly above the
    /// floor's own noise is a low object. Each slice is compared with the one before it, so ramps don't count.
    /// Must be seen in two checks in a row before it's said.
    func analyzeFloor(time: Double) {
        guard trustMonitor.isReliable, isGroundKnown else {
            floorInfo = nil
            floorCandidate = nil
            floorUncheckedSince = nil
            floorEndSince = nil
            return
        }
        let floorHeight = ground
        let start: Float = 0.3
        let size: Float = 0.2
        let count = 17
        let movers = tracker.tracks
            // Only people seen right now are cut out of the map: a hidden one's last place is the board they're behind.
            .filter { $0.kind.isMover && ($0.state == .sure || $0.state == .maybe) }
            .map { SIMD2($0.position.x, $0.position.z) }
        var bins = [[Float]](repeating: [], count: count)
        // For checkFloorEnd: per slice, points at the floor's level, well below it, and standing on it.
        var atLevel = [Int](repeating: 0, count: count)
        var deep = [Int](repeating: 0, count: count)
        var raised = [Int](repeating: 0, count: count)
        for cell in map.cells.values where cell.hits >= 2 && time - cell.lastSeen < 1.5 {
            let offset = SIMD2(cell.position.x - walker.position.x, cell.position.z - walker.position.z)
            let ahead = simd_dot(offset, walker.forward)
            guard ahead >= start, ahead < start + Float(count) * size else { continue }
            let lateral = simd_dot(offset, walker.left)
            guard abs(lateral) < 0.45 else { continue }
            let height = cell.position.y - floorHeight
            let slice = min(count - 1, Int((ahead - start) / size))
            if abs(height) < 0.12 { atLevel[slice] += 1 }
            if height <= -0.3 && height > -3 { deep[slice] += 1 }
            // Only what stands in the middle of the way hides the floor behind it; a railing or a side wall at the
            // edge of the corridor (stairs have them) does not.
            if height > 0.12 && height < 2 && abs(lateral) < 0.25 { raised[slice] += 1 }
            guard height > -0.9, height < 0.45 else { continue }
            let flatPosition = SIMD2(cell.position.x, cell.position.z)
            if movers.contains(where: { simd_distance($0, flatPosition) < 0.6 }) { continue }
            bins[slice].append(height)
        }

        var surface = [Float?](repeating: nil, count: count)
        var top = [Float](repeating: 0, count: count)
        var noise = [Float](repeating: 0, count: count)
        var sorted = [[Float]](repeating: [], count: count)
        for index in 0..<count where bins[index].count >= 4 {
            let heights = bins[index].sorted()
            let n = heights.count
            surface[index] = heights[n * 3 / 10]
            top[index] = heights[n * 9 / 10]
            noise[index] = max(0, (heights[n / 2] - heights[n / 10]) / 1.28)
            sorted[index] = heights
        }
        func nextSurface(after index: Int) -> Float? {
            for next in [index + 1, index + 2] where next < count {
                if let value = surface[next] { return value }
            }
            return nil
        }

        checkFloorEnd(level: atLevel, deep: deep, raised: raised, start: start, size: size, floorHeight: floorHeight, time: time)
        deepAhead = (deep.reduce(0, +), time)

        var found: FloorInfo?
        var previous: Float = 0
        var index = 0
        while index < count {
            guard let level = surface[index] else {
                index += 1
                continue
            }
            let distance = start + (Float(index) + 0.5) * size
            let jump = level - previous
            if abs(jump) >= 0.06, let next = nextSurface(after: index) {
                if jump > 0 && jump <= 0.35 && abs(next - previous) < 0.05 {
                    if found == nil { found = FloorInfo(kind: .lowObstacle, distance: distance, height: jump) }
                    index += 2
                    continue
                }
                let holds = abs(next - level) < 0.06 || (jump > 0 && next - level >= 0.06) || (jump < 0 && next - level <= -0.06)
                if holds {
                    if jump < -0.35 || jump > 0.35 { break }
                    previous = level
                    index += 1
                    continue
                }
            }
            if found == nil && distance < 2.5 {
                let threshold = max(distance < 2 ? Float(0.07) : 0.10, 3 * noise[index])
                let above = sorted[index].filter { $0 - level > threshold && $0 - level < 0.35 }.count
                if above >= max(4, Int(0.1 * Float(sorted[index].count))) {
                    found = FloorInfo(kind: .lowObstacle, distance: distance, height: top[index] - level)
                }
            }
            previous = level
            index += 1
        }

        guard let found else {
            floorInfo = nil
            floorCandidate = nil
            floorClearTime += 0.2
            if floorClearTime > 3 { floorSaid = nil }
            return
        }
        floorClearTime = 0
        if let candidate = floorCandidate, candidate.info.kind == found.kind,
           abs(candidate.info.distance - found.distance) < 0.6, time - candidate.time < 0.7 {
            floorInfo = found
            if floorSaid != found.kind {
                // Marked as said only once it is spoken; until then it waits its turn, refreshed with the latest distance.
                let kind = found.kind
                guide.handle(.floor(kind, distance: found.distance), time: time, key: "floor-near", maxWait: 1.0) { [weak self] in
                    self?.floorSaid = kind
                }
            }
            if found.distance < 2.5 {
                let interval = max(0.12, 0.12 + Double((found.distance - 0.6) / 1.9) * 0.7)
                if time - lastProximityTime >= interval {
                    lastProximityTime = time
                    guide.handle(.proximity, time: time)
                }
            }
        }
        floorCandidate = (found, time)
    }

    // MARK: where the floor ends (a platform edge, stairs going down)

    /// Switch for «Attenzione: non vedo il pavimento» and the paused tick, if they misfire in rehearsal.
    static let warnsWhereFloorEnds = true

    /// Floor was seen nearer, then two slices in a row that the camera is looking at have no floor at its level and
    /// nothing standing in front of them. With points well below, the floor ends there: that is said once, rank 1,
    /// because silence must never sound like "clear". With nothing below, the way can't be checked: only the
    /// "I can see" tick pauses. The look stops at the first thing standing on the floor (a board, a wall, a
    /// person): the floor behind it is hidden, not missing. Floor points are counted, not averaged, so the
    /// reflections a shiny floor puts below it can't hide the floor itself.
    func checkFloorEnd(level: [Int], deep: [Int], raised: [Int], start: Float, size: Float, floorHeight: Float, time: Double) {
        guard Self.warnsWhereFloorEnds, let camera = lastCamera else { return }
        func isInView(_ index: Int) -> Bool {
            let distance = start + (Float(index) + 0.5) * size
            let point = SIMD3<Float>(walker.position.x + walker.forward.x * distance, floorHeight,
                                     walker.position.z + walker.forward.y * distance)
            return camera.isInView(point)
        }
        func isFloor(_ index: Int) -> Bool { level[index] >= 4 }
        func isMissing(_ index: Int) -> Bool { level[index] < 2 && raised[index] < 3 && isInView(index) }

        var end: Int?
        // In a station (Apple's classifier, GuidancePipeline+Scene.swift) it looks further and needs fewer points below.
        let reach: Float = isStationLikely ? 3.0 : 2.5
        for index in 0..<(level.count - 1) where start + Float(index) * size <= reach {
            if raised[index] >= 3 { break }
            if isMissing(index) && isMissing(index + 1) {
                end = index
                break
            }
        }
        let below = end.map { deep[$0...].reduce(0, +) } ?? 0
        let endsHere = end != nil && below >= (isStationLikely ? 4 : 6)
        let sawFloorBefore = end.map { last in (0..<last).contains { isFloor($0) } } ?? false

        guard sawFloorBefore, let end else {
            if floorUncheckedSince != nil { log.write(["type": "floorEnd", "t": .number(time), "state": "clear"]) }
            floorUncheckedSince = nil
            floorEndSince = nil
            floorEndSaid = false
            return
        }
        let distance = start + Float(end) * size
        if floorUncheckedSince == nil {
            floorUncheckedSince = time
            log.write([
                "type": "floorEnd", "t": .number(time), "state": .text(endsHere ? "ends" : "unchecked"),
                "at": .number(Double(distance)), "below": .integer(below)
            ])
        }
        guard endsHere else {
            floorEndSince = nil
            return
        }
        if floorEndSince == nil { floorEndSince = time }
        // Held for two checks in a row, then said once, until the floor is seen again.
        if let since = floorEndSince, time - since >= 0.35, !floorEndSaid {
            lastDownWarningTime = time
            guide.handle(.floorEnds(distance: distance), time: time, key: "floor-end", maxWait: 1.0) { [weak self] in
                self?.floorEndSaid = true
            }
        }
    }

    /// The tick means "I can see the way": it pauses while the floor ahead, in view, can't be checked.
    func isFloorUnchecked(at time: Double) -> Bool {
        floorUncheckedSince.map { time - $0 >= 1.0 } ?? false
    }

    /// Points well below the floor in the walking corridor, in the last check: something goes down ahead.
    func isGoingDownAhead(at time: Double) -> Bool {
        time - deepAhead.time < 0.6 && deepAhead.count >= 6
    }

    /// A step up from the floor reader must be seen in the 3D map too: in the strip straight ahead, near where the
    /// reader puts it, the floor rises by a step's height (7–26 cm) and then stays up (a tread, a landing) or climbs
    /// by another step. A box falls back to the floor behind it, a table or a chair rises far more than a step, and
    /// nothing seen beyond the rise means it can't be told: none of these is a step.
    func isStepUpConfirmed(near distance: Float, time: Double) -> Bool {
        let size: Float = 0.2
        let start = max(0.3, distance - 0.8)
        let floorHeight = ground
        var slices = [[Float]](repeating: [], count: 10)
        for cell in map.cells.values where cell.hits >= 2 && time - cell.lastSeen < 1.5 {
            let offset = SIMD2(cell.position.x - walker.position.x, cell.position.z - walker.position.z)
            let ahead = simd_dot(offset, walker.forward)
            guard ahead >= start, abs(simd_dot(offset, walker.left)) < 0.3 else { continue }
            let index = Int((ahead - start) / size)
            let height = cell.position.y - floorHeight
            if index < slices.count && height > -0.15 && height < 1.0 { slices[index].append(height) }
        }
        let levels: [(index: Int, height: Float)] = slices.enumerated().compactMap { index, heights in
            guard heights.count >= 3 else { return nil }
            return (index, heights.sorted()[heights.count / 5])
        }
        for (floor, top) in zip(levels, levels.dropFirst()) {
            let riser = top.height - floor.height
            guard abs(floor.height) < 0.08, riser >= 0.07, riser <= 0.26 else { continue }
            guard let next = levels.first(where: { $0.index > top.index && $0.index <= top.index + 3 }) else { return false }
            let change = next.height - top.height
            if change >= -0.05 && change <= 0.25 { return true }
        }
        return false
    }
}
