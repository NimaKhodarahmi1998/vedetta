import ARKit
import simd

/// Obstacles the walker marks with a long press, and the place they belong to.
///
/// A mark sits on the floor at the obstacle: the nearest thing the map sees ahead within 2 m, else one pace ahead.
/// Walking towards it later, «Ostacolo segnato, tra N passi» is said once per approach. A long press on a marked spot
/// takes the mark away. Marks are ARKit anchors, so they are saved with ARKit's map of the place (no LiDAR needed)
/// and come back on the next walk once ARKit recognises the place; if it hasn't within 10 s, the walk goes on
/// without them and says so.
nonisolated extension GuidancePipeline {
    static let markName = "fieldvision-mark"
    /// Switch for saving the place and loading it on the next start, if it misbehaves.
    /// Off for the demo: loading a saved place held up every start for up to 10 s, and saving the whole map every
    /// minute was heavy. Marks still work during a walk.
    static let remembersPlaces = false
    static let relocalizationTimeout = 10.0

    static var placeURL: URL { URL.documentsDirectory.appending(path: "fieldvision-place.arworldmap") }

    /// The place saved last time, if it holds any marks.
    static func savedPlace() -> ARWorldMap? {
        guard remembersPlaces, let data = try? Data(contentsOf: placeURL),
              let place = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data),
              place.anchors.contains(where: { $0.name == markName }) else { return nil }
        return place
    }

    /// A long press: marks the obstacle ahead, or takes away the mark already there.
    func markObstacle() {
        queue.async { [self] in
            guard frameTime > 0 else { return }
            let time = frameTime
            let reach = max(0.5, min(2.0, pathAhead?.distance ?? floorInfo?.distance ?? 0.7))
            let spot = SIMD2(walker.position.x, walker.position.z) + walker.forward * reach
            if let existing = marks.first(where: { simd_distance(SIMD2($0.value.x, $0.value.z), spot) < 0.6 })?.key {
                if let anchor = session.currentFrame?.anchors.first(where: { $0.identifier == existing }) {
                    session.remove(anchor: anchor)
                }
                marks[existing] = nil
                guide.handle(.markRemoved, time: time)
                log.write([
                    "type": "markObstacle", "t": .number(time), "action": "removed",
                    "x": .number(Double(spot.x)), "z": .number(Double(spot.y))
                ])
            } else {
                var transform = matrix_identity_float4x4
                transform.columns.3 = SIMD4(spot.x, ground, spot.y, 1)
                let anchor = ARAnchor(name: Self.markName, transform: transform)
                session.add(anchor: anchor)
                marks[anchor.identifier] = SIMD3(spot.x, ground, spot.y)
                warnedMarks.insert(anchor.identifier)
                guide.handle(.markAdded, time: time)
                log.write([
                    "type": "markObstacle", "t": .number(time), "action": "added", "d": .number(Double(reach)),
                    "x": .number(Double(spot.x)), "z": .number(Double(spot.y))
                ])
            }
            savePlace(time: time)
        }
    }

    /// Restored marks arrive as anchors once ARKit recognises the saved place; our own new ones arrive here too.
    func addMarks(from anchors: [ARAnchor]) {
        for anchor in anchors where anchor.name == Self.markName {
            let column = anchor.transform.columns.3
            marks[anchor.identifier] = SIMD3(column.x, column.y, column.z)
        }
    }

    /// Walking towards a marked obstacle: said once per approach, from 2 m; again after walking 3 m away.
    /// While marks exist, the place is saved again every minute, so the next walk recognises it better.
    func checkMarks(time: Double) {
        guard !marks.isEmpty else { return }
        if time - lastPlaceSaveTime > 60 { savePlace(time: time) }
        guard trustMonitor.isReliable, !isLoadingPlace else { return }
        for (id, position) in marks {
            let offset = SIMD2(position.x - walker.position.x, position.z - walker.position.z)
            let ahead = simd_dot(offset, walker.forward)
            let lateral = simd_dot(offset, walker.left)
            if ahead > 0.2 && ahead < 2.0 && abs(lateral) < 0.6 {
                guard !warnedMarks.contains(id) else { continue }
                warnedMarks.insert(id)
                guide.handle(.markAhead(distance: ahead), time: time, key: "mark")
                log.write(["type": "markAhead", "t": .number(time), "d": .number(Double(ahead))])
            } else if simd_length(offset) > 3 {
                warnedMarks.remove(id)
            }
        }
    }

    /// Saves ARKit's map of this place with its marks for the next walk here; with no marks left, forgets it.
    func savePlace(time: Double) {
        guard Self.remembersPlaces, !isLoadingPlace else { return }
        lastPlaceSaveTime = time
        guard !marks.isEmpty else {
            try? FileManager.default.removeItem(at: Self.placeURL)
            return
        }
        session.getCurrentWorldMap { [weak self] place, error in
            guard let self else { return }
            guard let place else {
                log.write(["type": "placeSave", "ok": .flag(false), "error": .text(error?.localizedDescription ?? "")])
                return
            }
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: place, requiringSecureCoding: true)
                try data.write(to: Self.placeURL, options: .atomic)
                let count = place.anchors.filter { $0.name == Self.markName }.count
                log.write(["type": "placeSave", "ok": .flag(true), "marks": .integer(count)])
            } catch {
                log.write(["type": "placeSave", "ok": .flag(false), "error": .text(error.localizedDescription)])
            }
        }
    }

    /// On every frame while a saved place is loading: recognised once its marks come back; given up after 10 s.
    func followPlaceLoading(time: Double) {
        guard isLoadingPlace else { return }
        if relocalizationStart == nil { relocalizationStart = time }
        if !marks.isEmpty {
            isLoadingPlace = false
            // The world just moved onto the saved place: what was mapped meanwhile is dropped.
            resetSpatialState()
            guide.handle(.placeRecognized(marks: marks.count), time: time)
            log.write(["type": "placeLoad", "t": .number(time), "ok": .flag(true), "marks": .integer(marks.count)])
        } else if let start = relocalizationStart, time - start > Self.relocalizationTimeout {
            isLoadingPlace = false
            guide.handle(.placeNotRecognized, time: time)
            log.write(["type": "placeLoad", "t": .number(time), "ok": .flag(false)])
            DispatchQueue.main.async { [self] in runFreshSession() }
        }
    }

    /// The saved place was not recognised: guidance goes on in a fresh session, without the saved marks
    /// (the saved place stays for next time, unless a new mark is made here).
    func runFreshSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.worldAlignment = .gravity
        configuration.isLightEstimationEnabled = true
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        queue.async { [self] in
            resetSpatialState()
            marks = [:]
            warnedMarks = []
        }
    }

    func resetSpatialState() {
        map.reset()
        tracker.reset()
        planeGround = nil
        pointGround = nil
        depthScale = DepthScale()
        pathAhead = nil
        hasSaidAhead = false
        steps.reset()
        stepSay.reset()
        floorScale = DepthScale()
        stepViews = []
        floorInfo = nil
        floorCandidate = nil
        floorSaid = nil
        warnedMarks = []
        store.setMap([])
    }
}
