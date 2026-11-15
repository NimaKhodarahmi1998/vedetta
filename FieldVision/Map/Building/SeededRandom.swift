/// Deterministic, so the splat shapes are the same on every launch.
nonisolated struct SeededRandom {
    private static let multiplier: UInt64 = 6364136223846793005
    private static let increment: UInt64 = 1442695040888963407

    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* Self.multiplier &+ Self.increment
    }

    mutating func next() -> Float {
        state = state &* Self.multiplier &+ Self.increment
        return Float(state >> 40) / Float(1 << 24)
    }
}
