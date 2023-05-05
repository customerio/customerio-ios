import Foundation
import SwiftUI

struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .resizable()
                .frame(width: 30, height: 30)
        }
    }
}

struct SettingsButton_Previews: PreviewProvider {
    static var previews: some View {
        SettingsButton {}
    }
}
