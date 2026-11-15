import SwiftUI

/// The chip that names a tracked object, on the camera and on the map.
struct MarkerLabel: View {
    let text: String
    let style: MarkerStyle

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(style == .danger ? Color.black : style.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(style == .danger ? style.color : Color.black.opacity(0.6), in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style.color, style: StrokeStyle(lineWidth: 1, dash: style.dash))
            }
            .fixedSize()
    }
}
