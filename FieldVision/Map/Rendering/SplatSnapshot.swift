nonisolated struct SplatSnapshot {
    /// Empty when the caller already holds this version.
    let mapVertices: [SplatVertex]
    let mapVersion: Int
    let overlayVertices: [SplatVertex]
    let walker: SIMD3<Float>
    let forward: SIMD2<Float>
    let ground: Float
    let isReliable: Bool
    let waveStartTime: Double
    let theme: MapTheme
}
