/// Changes in the floor ahead: passable with care (steps, stairs), dangerous (a drop), or a low object.
nonisolated enum FloorKind: String {
    case stepUp, stepDown, stairsUp, stairsDown, dropOff, lowObstacle

    var isUp: Bool { self == .stepUp || self == .stairsUp }
}
