/// Turns the model's relative output into metres: 1/z = scale * relative + offset, fitted on ARKit feature points.
/// Kept for a few seconds, so a plain wall is still measured while walking up to it.
nonisolated struct DepthScale {
    private(set) var isValid = false
    private(set) var pairsUsed = 0
    private var scale: Float = 0
    private var offset: Float = 0
    private var lastFitTime = -99.0

    /// Least squares on inverse depth, refitted up to three times without the outliers.
    mutating func fit(_ pairs: [(relative: Float, depth: Float)], time: Double) {
        if time - lastFitTime > 6 { isValid = false }
        guard pairs.count >= 8 else { return }
        var inliers = pairs
        for _ in 0..<3 {
            let count = Float(inliers.count)
            var sumX: Float = 0
            var sumY: Float = 0
            var sumXX: Float = 0
            var sumXY: Float = 0
            for pair in inliers {
                let inverseDepth = 1 / pair.depth
                sumX += pair.relative
                sumY += inverseDepth
                sumXX += pair.relative * pair.relative
                sumXY += pair.relative * inverseDepth
            }
            let denominator = count * sumXX - sumX * sumX
            guard abs(denominator) > 1e-9 else { return }
            let slope = (count * sumXY - sumX * sumY) / denominator
            let intercept = (sumY - slope * sumX) / count
            let residuals = inliers.map { abs(1 / $0.depth - (slope * $0.relative + intercept)) }
            let medianResidual = residuals.sorted()[residuals.count / 2]
            let residualLimit = max(0.02, 2.5 * medianResidual)
            let kept = zip(inliers, residuals).filter { _, residual in residual <= residualLimit }.map { pair, _ in pair }
            if slope > 0 {
                scale = slope
                offset = intercept
                isValid = true
                lastFitTime = time
                pairsUsed = inliers.count
            }
            if kept.count < 8 || kept.count == inliers.count { break }
            inliers = kept
        }
    }

    /// Read-only, for the floor reader's depth grid (1/z = slope * relative + intercept).
    var slope: Float { scale }
    var intercept: Float { offset }
    var fittedAt: Double { lastFitTime }

    /// Nil when the scale isn't known or the value is out of range.
    func metres(fromRelative relative: Float) -> Float? {
        guard isValid else { return nil }
        let inverseDepth = scale * relative + offset
        guard inverseDepth > 1.0 / 25.0 else { return nil }
        return max(0.2, 1 / inverseDepth)
    }
}
