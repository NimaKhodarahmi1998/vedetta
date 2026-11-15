import SwiftUI

/// The glass button styles, with the bordered styles on systems before them.
struct GlassButton: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if isProminent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func glassButton(isProminent: Bool = false) -> some View {
        modifier(GlassButton(isProminent: isProminent))
    }
}
