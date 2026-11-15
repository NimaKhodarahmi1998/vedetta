/// Decides what is said and when. Every line has a rank, 1 the most important. A line only cuts in on a lower-ranked
/// one; everything else waits its turn in a short queue instead of being dropped.
///
/// 1 a drop or stairs going down · 2 guidance unreliable · 3 something fast coming · 4 anything under 2 m
/// 5 torch, guidance on or back · 6 ahead, steps · 7 hidden, back in view, lost, crowd
nonisolated final class Guide {
    /// The shortest gap between the starts of two calm lines (ranks 6 and 7), so the walker isn't talked at.
    static let spacing = 2.5
    /// Lines up to this rank may cut in on a lower-ranked one and don't wait for the spacing.
    static let cutInRank = 5
    /// At most this many lines wait; past it, the least important, oldest one goes.
    static let maxWaiting = 5

    let language: Language
    var onUtterance: (@Sendable (Utterance) -> Void)?

    nonisolated private struct Line {
        let text: String
        let cue: Cue?
        let rank: Int
        let key: String?
        let time: Double
        let maxWait: Double
        let onSpoken: (() -> Void)?
    }

    private let log: EventLog
    private var waiting: [Line] = []
    private var lastSpokenTime = -99.0
    private var speakingRank = Int.max
    private var speakingUntil = -99.0

    init(log: EventLog, language: Language) {
        self.log = log
        self.language = language
    }

    /// key: a newer line with the same key replaces the one still waiting. maxWait: how long it may wait to be said.
    /// onSpoken: runs once the line is actually said.
    func handle(_ event: GuideEvent, time: Double, key: String? = nil, maxWait: Double? = nil, onSpoken: (() -> Void)? = nil) {
        switch event {
            case .tick: play(.tick)
            case .buzz: play(.long)
            case .proximity: play(.proximity)
            default:
                if let line = line(for: event) {
                    say(Line(text: line.text, cue: line.cue, rank: line.rank, key: key ?? line.key, time: time,
                             maxWait: maxWait ?? Self.maxWait(forRank: line.rank), onSpoken: onSpoken), time: time)
                }
        }

        switch event {
            case .tick, .proximity: break
            default: log.write(["type": "event", "t": .number(time), "event": .text(String(describing: event))])
        }
    }

    /// Called on every frame, so a waiting line goes out as soon as there's room for it.
    func flush(time: Double) {
        waiting.removeAll { line in
            guard time - line.time > line.maxWait else { return false }
            log.write(["type": "drop", "t": .number(time), "text": .text(line.text), "rank": .integer(line.rank)])
            return true
        }
        guard time >= speakingUntil + 0.15,
              let next = waiting.indices.min(by: { (waiting[$0].rank, waiting[$0].time) < (waiting[$1].rank, waiting[$1].time) })
        else { return }
        let line = waiting[next]
        guard line.rank <= Self.cutInRank || time - lastSpokenTime >= Self.spacing else { return }
        waiting.remove(at: next)
        emit(line, time: time, interrupts: false)
    }

    private func say(_ line: Line, time: Double) {
        if let key = line.key { waiting.removeAll { $0.key == key } }
        // Cuts in only on a lower-ranked line; an equal or more important one finishes first.
        if time < speakingUntil && line.rank <= Self.cutInRank && line.rank < speakingRank {
            emit(line, time: time, interrupts: true)
            return
        }
        waiting.append(line)
        if waiting.count > Self.maxWaiting,
           let worst = waiting.indices.max(by: { (waiting[$0].rank, -waiting[$0].time) < (waiting[$1].rank, -waiting[$1].time) }) {
            log.write(["type": "drop", "t": .number(time), "text": .text(waiting[worst].text), "rank": .integer(waiting[worst].rank)])
            waiting.remove(at: worst)
        }
        flush(time: time)
    }

    private func emit(_ line: Line, time: Double, interrupts: Bool) {
        lastSpokenTime = time
        speakingRank = line.rank
        speakingUntil = time + Self.duration(of: line.text)
        log.write([
            "type": "say", "t": .number(time), "text": .text(line.text), "lang": .text(language.rawValue),
            "rank": .integer(line.rank), "waited": .number(time - line.time)
        ])
        onUtterance?(Utterance(text: line.text, cue: line.cue, interrupts: interrupts, language: language))
        line.onSpoken?()
    }

    private func play(_ cue: Cue) {
        onUtterance?(Utterance(text: nil, cue: cue, interrupts: false, language: language))
    }

    private func line(for event: GuideEvent) -> (text: String, cue: Cue?, rank: Int, key: String?)? {
        switch event {
            case .start:
                return (SpokenLine.start(in: language), Cue.tick, 5, "trust")
            case .ahead(let kind, let isClose):
                return (SpokenLine.ahead(kind, isClose: isClose, in: language), Cue.knock, isClose ? 4 : 6, "ahead-\(kind)")
            case .hidden(let kind, let isLeft):
                return (SpokenLine.hidden(kind, isLeft: isLeft, in: language), Cue.flutter, 7, "seen-\(kind)")
            case .back(let kind, let isLeft):
                return (SpokenLine.back(kind, isLeft: isLeft, in: language), Cue.knock, 7, "seen-\(kind)")
            case .lost(let kind):
                return (SpokenLine.lost(kind, in: language), nil, 7, "seen-\(kind)")
            case .fast(let kind, let isLeft):
                return (SpokenLine.fast(kind, isLeft: isLeft, in: language), Cue.fast, 3, "fast")
            case .unreliable(let reason):
                return (SpokenLine.unreliable(reason, in: language), Cue.long, 2, "trust")
            case .reliable(let withTorch):
                return (SpokenLine.reliable(withTorch: withTorch, in: language), Cue.rising, 5, "trust")
            case .obstacle:
                return (SpokenLine.obstacle(in: language), Cue.knock, 4, "path")
            case .crowd:
                return (SpokenLine.crowd(in: language), nil, 7, "crowd")
            case .torchOn:
                return (SpokenLine.torchOn(in: language), Cue.torch, 5, "torch")
            case .torchOff:
                return (SpokenLine.torchOff(in: language), Cue.torch, 5, "torch")
            case .wall(let isClose, let opening):
                return (SpokenLine.wall(isClose: isClose, opening: opening, in: language), Cue.knock, isClose ? 4 : 6, "path")
            case .floor(let kind, let distance):
                let cue: Cue = kind == .lowObstacle ? .knock : .step
                return (SpokenLine.floor(kind, distance: distance, in: language), cue,
                        Self.floorRank(kind, distance: distance, isNear: true, isUrgent: false), nil)
            case .floorFar(let kind, let distance, let side, let isUrgent):
                return (SpokenLine.floorFar(kind, distance: distance, side: side, in: language), Cue.step,
                        Self.floorRank(kind, distance: distance, isNear: false, isUrgent: isUrgent), nil)
            case .floorEnds:
                return (SpokenLine.floorEnds(in: language), Cue.fast, 1, "floor-end")
            case .markAdded:
                return (SpokenLine.markAdded(in: language), Cue.knock, 5, "mark-edit")
            case .markRemoved:
                return (SpokenLine.markRemoved(in: language), nil, 5, "mark-edit")
            case .markAhead(let distance):
                return (SpokenLine.markAhead(distance: distance, in: language), Cue.knock, 4, "mark")
            case .placeRecognized(let marks):
                return (SpokenLine.placeRecognized(marks: marks, in: language), nil, 5, "place")
            case .placeNotRecognized:
                return (SpokenLine.placeNotRecognized(in: language), nil, 5, "place")
            case .stairsLikely:
                return (SpokenLine.stairsLikely(in: language), Cue.step, 6, "scene")
            case .tick, .buzz, .proximity:
                return nil
        }
    }

    /// «riapparsa» and the other calm lines wait the longest for their turn; a warning is only worth it soon.
    private static func maxWait(forRank rank: Int) -> Double {
        switch rank {
            case ...4: return 3
            case 5, 6: return 4
            default: return 6
        }
    }

    /// A drop or stairs going down close by come first; anything under 2 m, or urgent from far, next.
    private static func floorRank(_ kind: FloorKind, distance: Float, isNear: Bool, isUrgent: Bool) -> Int {
        let goesDown = kind == .dropOff || kind == .stairsDown
        if goesDown && (isNear || isUrgent) { return 1 }
        if (isNear && distance < 2) || isUrgent { return 4 }
        return 6
    }

    /// About 15 characters a second at the voice's pace.
    private static func duration(of text: String) -> Double { 0.3 + Double(text.count) / 15 }
}
