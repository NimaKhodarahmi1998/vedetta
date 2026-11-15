nonisolated enum GuideEvent {
    case start
    case ahead(ObjectKind, isClose: Bool)
    case hidden(ObjectKind, isLeft: Bool)
    case back(ObjectKind, isLeft: Bool)
    case lost(ObjectKind)
    case fast(ObjectKind, isLeft: Bool)
    case unreliable(UnreliableReason)
    /// withTorch: guidance is back thanks to the torch, so it only sees close by.
    case reliable(withTorch: Bool)
    case obstacle
    case crowd
    case tick
    case buzz
    case proximity
    case torchOn
    case torchOff
    case wall(isClose: Bool, opening: PathOpening)
    /// A floor change close by, in the walking path.
    case floor(FloorKind, distance: Float)
    /// A step or staircase seen early, up to 30 m away. side: +1 left, -1 right, 0 ahead.
    case floorFar(FloorKind, distance: Float, side: Int, isUrgent: Bool)
    /// No floor where the camera is looking, and points well below it: a platform edge or stairs going down.
    case floorEnds(distance: Float)
    /// Apple's classifier sees stairs in 2 of its last 3 looks: a hint, said before the floor reader is sure.
    case stairsLikely
    /// Obstacles marked with a long press, and the saved place they belong to.
    case markAdded
    case markRemoved
    case markAhead(distance: Float)
    case placeRecognized(marks: Int)
    case placeNotRecognized
}
