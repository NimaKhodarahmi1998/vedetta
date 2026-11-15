/// The map's monochrome look: the ground colour the scene fades into, and the ink everything is drawn in.
nonisolated struct MapTheme {
    let ground: SIMD3<Float>
    let ink: SIMD3<Float>

    static let light = MapTheme(ground: SIMD3(0.91, 0.91, 0.92), ink: SIMD3(0.16, 0.16, 0.18))
    static let dark = MapTheme(ground: SIMD3(0.08, 0.08, 0.09), ink: SIMD3(0.93, 0.93, 0.94))

    /// A grey between the ground (0) and the ink (1).
    func tone(_ amount: Float) -> SIMD3<Float> {
        ground + (ink - ground) * amount
    }
}
