import Foundation
import SwiftUI

struct ColorButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            action()
        }) {
            Text(title)
                .foregroundColor(.white)
        }
        .buttonStyle(BorderedProminentButtonStyle())
        .background(Color.accentColor)
    }
}

struct ColorButton_Previews: PreviewProvider {
    static var previews: some View {
        ColorButton(title: "Send random event") {}
    }
}
