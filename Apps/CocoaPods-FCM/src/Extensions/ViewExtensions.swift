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
}
