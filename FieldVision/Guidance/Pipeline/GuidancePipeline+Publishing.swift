nonisolated extension GuidancePipeline {
    func publish(time: Double) {
        let isReliable = trustMonitor.isReliable
        let language = guide.language
        let shown = tracker.tracks
            .filter { $0.state == .maybe || $0.state == .sure || $0.state == .hidden }
            .sorted { priority(of: $0) > priority(of: $1) }

        var boxes: [DetectionBox] = []
        for (rank, track) in shown.enumerated()
        where track.state != .hidden && time - track.lastSeen < 0.5 && (track.state == .sure || track.isRelevant) {
            let (text, style) = label(for: track, isReliable: isReliable, language: language)
            let isNamed = rank < Self.maxLabels && (track.state != .maybe || track.isRelevant)
            boxes.append(DetectionBox(id: track.id, rect: track.box, text: isNamed ? text : "", style: style))
        }
        let items = isReliable ? shown.prefix(Self.maxLabels).map(sceneItem(for:)) : []
        let state = PipelineState(
            boxes: boxes,
            items: items,
            pathAhead: isReliable ? pathAhead : nil,
            isReliable: isReliable,
            reason: trustMonitor.reason,
            isTorchOn: torch.isOn
        )
        onStateChange?(state)
    }

    private func sceneItem(for track: Track) -> SceneItem {
        let direction: SceneDirection
        if track.aheadDistance < 0 {
            direction = .behind
        } else if abs(track.lateralOffset) < 0.6 {
            direction = .ahead
        } else {
            direction = track.lateralOffset > 0 ? .left : .right
        }
        return SceneItem(kind: track.kind, distance: track.distance, direction: direction, state: track.state, isFast: track.isFast)
    }

    /// Who gets a label: danger first, then hidden in the path, in the path, near, the rest.
    private func priority(of track: Track) -> Float {
        if track.isFast || track.isDanger { return 5 }
        if track.state == .hidden && track.isRelevant { return 4 }
        if track.isInPath { return 3 }
        if track.isRelevant { return 2 }
        if track.state == .sure { return 1 - min(1, track.distance / Self.maxRange) }
        return 0
    }

    private func label(for track: Track, isReliable: Bool, language: Language) -> (String, MarkerStyle) {
        let name = track.kind.name(in: language) + " \(track.id)"
        let isFeminine = track.kind.isFeminine
        guard isReliable else { return (name + language.text(" · dalla memoria", " · from memory"), .frozen) }
        if track.isFast { return (name + language.text(" · veloce", " · fast"), .danger) }
        let distance = (track.isOnGround ? "" : "≈") + language.number(track.distance) + " m"
        switch track.state {
            case .hidden:
                let hidden = language.text(isFeminine ? " · nascosta da " : " · nascosto da ", " · hidden for ")
                return (name + hidden + language.number(Float(track.hiddenTime)) + " s", .hidden)
            case .maybe:
                return (language.text("Oggetto", "Object") + " \(track.id) · " + language.text("forse", "maybe") + " · " + distance, .maybe)
            default:
                let confirmed = language.text(isFeminine ? "confermata" : "confermato", "confirmed")
                let ahead = track.isInPath ? language.text(" · davanti", " · ahead") : ""
                return (name + " · " + confirmed + " · " + distance + ahead, track.isDanger ? .danger : .sure)
        }
    }

    func logState(time: Double) {
        let tracks = tracker.tracks
        let opening: Int
        switch pathAhead?.opening ?? .none {
            case .none: opening = 0
            case .left: opening = 1
            case .right: opening = -1
        }
        let groundSource = planeGround != nil ? "plane" : (pointGround != nil ? "points" : "guess")
        log.write([
            "type": "state",
            "t": .number(time),
            "trust": .number(Double(trustMonitor.trust)),
            "reliable": .flag(trustMonitor.isReliable),
            // Where the walker is on the floor, for the seen / not seen route map (tools/route_map.py).
            "x": .number(Double(walker.position.x)),
            "z": .number(Double(walker.position.z)),
            "reason": .text(trustMonitor.reason?.rawValue ?? ""),
            "weakest": .text(trustMonitor.weakestSignal.rawValue),
            "tracks": .integer(tracks.count),
            "sure": .integer(tracks.filter { $0.state == .sure }.count),
            "hidden": .integer(tracks.filter { $0.state == .hidden }.count),
            "voxels": .integer(map.cells.count),
            "fps": .number(framesPerSecond),
            "detHz": .number(detectionRate),
            "detMs": .number(detectionMilliseconds),
            "depthHz": .number(depthRate),
            "depthMs": .number(depthMilliseconds),
            "depthValid": .flag(depthScale.isValid),
            "depthPairs": .integer(depthScale.pairsUsed),
            "ahead": .number(pathAhead.map { Double($0.distance) } ?? -1),
            "wall": .flag(pathAhead?.isWall ?? false),
            "opening": .integer(opening),
            "ground": .text(groundSource),
            "luma": .number(Double(luma.mean)),
            "lumaStd": .number(Double(luma.deviation)),
            "torch": .flag(torch.isOn),
            "floor": .text(floorInfo?.kind.rawValue ?? ""),
            "floorDist": .number(floorInfo.map { Double($0.distance) } ?? -1),
            "step": .text(stepViews.first?.f.kind.rawValue ?? ""),
            "stepDist": .number(stepViews.first.map { Double($0.sayDistance) } ?? -1),
            "stepRise": .number(stepViews.first.map { Double($0.f.rise) } ?? 0),
            "stepInPath": .flag(stepViews.first?.inPath ?? false),
            "steps": .integer(steps.features.filter { $0.confirmed }.count),
            "floorFit": .flag(floorScale.isValid),
            "lowLight": .flag(lowLight.active),
            "gain": .number(Double(lowLight.gain)),
        ])
    }
}
