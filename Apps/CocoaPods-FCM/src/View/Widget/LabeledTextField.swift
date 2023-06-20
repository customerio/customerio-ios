import Foundation
import SwiftUI

struct LabeledTextField: View {
    var title: String
    var appiumTextFieldId: String = "" // make id optional

    @Binding var value: String

    var body: some View {
        HStack {
            Text(title)
            VStack {
                TextField("", text: $value)
                    .setAppiumId(appiumTextFieldId)
                Divider()
            }
        }
    }
}
