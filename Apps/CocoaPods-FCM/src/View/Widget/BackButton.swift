import Foundation
import SwiftUI

// Custom back button that resembles the iOS provided back button in a navigation bar.
// Providing a custom back button so we can set an appium ID.
struct BackButton: View {
    let onClick: () -> Void

    var body: some View {
        VStack {
            Button(action: {
                onClick()
            }) {
                Image(systemName: "chevron.backward").font(.system(size: 24))
            }
            .setAppiumId("Back")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.leading, .top], 15)
            Spacer()
        }
    }
}
