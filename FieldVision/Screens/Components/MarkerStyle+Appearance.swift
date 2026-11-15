import SwiftUI

extension MarkerStyle {
    var color: Color {
        switch self {
            case .maybe: .orange
            case .sure, .hidden: .cyan
            case .danger: .red
            case .frozen: .gray
        }
    }

    /// Maybe is dashed and hidden is dotted, so the state reads without colour too.
    var dash: [CGFloat] {
        switch self {
            case .maybe: [5, 3]
            case .hidden: [1.5, 2.5]
            case .sure, .danger, .frozen: []
        }
    }
}
