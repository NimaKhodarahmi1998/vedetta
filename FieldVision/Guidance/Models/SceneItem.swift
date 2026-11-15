/// One tracked object, as the map describes it to VoiceOver.
nonisolated struct SceneItem {
    let kind: ObjectKind
    let distance: Float
    let direction: SceneDirection
    let state: TrackState
    let isFast: Bool
}
