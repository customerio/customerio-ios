import Foundation
import SwiftUI

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
