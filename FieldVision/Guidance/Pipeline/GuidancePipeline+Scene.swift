import CoreVideo

nonisolated extension GuidancePipeline {
    /// A score at or above this counts as one vote for stairs or a station.
    static let sceneThreshold: Float = 0.5

    /// Once a second, Apple's classifier is asked what kind of place this is.
    func requestScene(in pixelBuffer: CVPixelBuffer, time: Double) {
        isSceneBusy = true
        lastSceneTime = time
        scene.classify(pixelBuffer) { [weak self] stairs, station, top in
            guard let self else { return }
            queue.async { self.handleScene(stairs: stairs, station: station, top: top, time: time) }
        }
    }

    /// Stairs or a station are believed only when 2 of the last 3 answers agree. Stairs make far step lines come
    /// sooner and say «Possibili scale davanti» once; a station makes the floor-end check reach further and trigger
    /// on fewer points below. Neither ever delays or silences a warning.
    private func handleScene(stairs: Float, station: Float, top: String, time: Double) {
        isSceneBusy = false
        stairsVotes = Array((stairsVotes + [stairs >= Self.sceneThreshold]).suffix(3))
        stationVotes = Array((stationVotes + [station >= Self.sceneThreshold]).suffix(3))
        let wasStairs = isStairsLikely
        // Stairs only when all 3 of the last looks agree: furniture fooled it at 2 of 3.
        isStairsLikely = stairsVotes.count == 3 && !stairsVotes.contains(false)
        isStationLikely = stationVotes.filter { $0 }.count >= 2
        stepSay.isStairsLikely = isStairsLikely
        log.write([
            "type": "scene", "t": .number(time), "stairs": .number(Double(stairs)), "station": .number(Double(station)),
            "top": .text(top), "stairsLikely": .flag(isStairsLikely), "stationLikely": .flag(isStationLikely)
        ])
        if isStairsLikely && !wasStairs && time - lastStairsHintTime > 30 {
            lastStairsHintTime = time
            guide.handle(.stairsLikely, time: time)
        }
    }

    func logSceneLabels() {
        scene.checkLabels { [weak self] found, missing, system in
            guard let self else { return }
            log.write(["type": "labels", "found": .text(found.joined(separator: " ")),
                       "missing": .text(missing.joined(separator: " ")), "system": .text(system)])
            print("[FieldVision] Vision place labels on this phone: \(found.joined(separator: ", ")). Missing: \(missing.joined(separator: ", ")). \(system)")
        }
    }
}
