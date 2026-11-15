import CoreGraphics

/// Vision coordinates: upright image, normalized, origin bottom-left.
nonisolated struct ImageDetection {
    let label: String
    let confidence: Float
    let box: CGRect
}
