import SwiftUI

extension View {
    func setBackgroundColor(_ color: Color) -> some View {
        background(AnyView(Capsule().fill(color)))
    }

    func fullScreenFrame() -> some View {
        frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    // Adds a border around View for convenience during development. Be able to view the size easily.
    func debugSize() -> some View {
        border(Color.random, width: 1)
    }

    func hideKeyboard() { // this also makes all TextFields lose focus
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
