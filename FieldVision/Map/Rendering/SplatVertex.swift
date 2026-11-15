/// Layout must match SplatIn in the Metal source: 9 floats, 36 bytes.
nonisolated struct SplatVertex {
    let positionX: Float
    let positionY: Float
    let positionZ: Float
    let red: Float
    let green: Float
    let blue: Float
    /// Certainty 0...1 for map splats, alpha for overlays.
    let confidence: Float
    /// World size in metres.
    let size: Float
    let mode: Float

    init(position: SIMD3<Float>, color: SIMD3<Float>, confidence: Float, size: Float, mode: SplatMode) {
        positionX = position.x
        positionY = position.y
        positionZ = position.z
        red = color.x
        green = color.y
        blue = color.z
        self.confidence = confidence
        self.size = size
        self.mode = mode.rawValue
    }
}
