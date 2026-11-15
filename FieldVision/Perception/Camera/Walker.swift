import simd

/// The person wearing the phone, on the ground plane.
nonisolated struct Walker {
    var position = SIMD3<Float>(0, 0, 0)
    /// Unit vector on the ground, as (x, z).
    var forward = SIMD2<Float>(0, -1)

    var left: SIMD2<Float> {
        SIMD2(forward.y, -forward.x)
    }
}
