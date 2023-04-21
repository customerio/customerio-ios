import SwiftUI

extension View {
    func setBackgroundColor(_ color: Color) -> some View {
        background(AnyView(Capsule().fill(color)))
    }
}
