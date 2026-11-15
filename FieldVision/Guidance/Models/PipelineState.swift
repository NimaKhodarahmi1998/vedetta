/// What the interface shows, published by the pipeline about 12 times a second.
nonisolated struct PipelineState {
    let boxes: [DetectionBox]
    let items: [SceneItem]
    let pathAhead: PathAhead?
    let isReliable: Bool
    let reason: UnreliableReason?
    let isTorchOn: Bool
}
