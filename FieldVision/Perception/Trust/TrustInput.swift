import ARKit

nonisolated struct TrustInput {
    var trackingState: ARCamera.TrackingState
    var ambientIntensity: Float?
    var lumaMean: Float
    var lumaDeviation: Float
    /// With the torch on, ARKit's light estimate measures the torch, so it is left out.
    var isTorchOn: Bool = false
    /// A hand on the lens (see GuidancePipeline.updateLensCover): named even when the picture is also dark.
    var isLensCovered: Bool = false
}
