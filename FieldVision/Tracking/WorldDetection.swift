import CoreGraphics
import simd

/// One detection placed in the world, in metres and ARKit coordinates.
nonisolated struct WorldDetection {
    let kind: ObjectKind
    let confidence: Float
    let position: SIMD3<Float>
    /// Camera image, normalized, top-left origin.
    let box: CGRect
    /// Placed by a ray to the ground, rather than estimated from the box height.
    let isOnGround: Bool
}
