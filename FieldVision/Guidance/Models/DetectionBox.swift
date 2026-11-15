import CoreGraphics

nonisolated struct DetectionBox: Identifiable {
    let id: Int
    /// Camera image, normalized, top-left origin.
    let rect: CGRect
    /// Empty for a box drawn without a label.
    let text: String
    let style: MarkerStyle
}
