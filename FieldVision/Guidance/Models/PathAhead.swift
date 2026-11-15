/// What blocks the walking path, found in the 3D map from feature points, depth and wall planes.
nonisolated struct PathAhead {
    var distance: Float
    var isWall: Bool
    var opening: PathOpening

    /// Close enough to be a danger: walls are judged nearer than obstacles.
    var isClose: Bool { distance < (isWall ? 1.5 : 3) }
}
