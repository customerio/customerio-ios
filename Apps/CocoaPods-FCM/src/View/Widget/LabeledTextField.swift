import Foundation
import SwiftUI

// A TextField with a label on the left side.
// Accepts many different types of data.
struct LabeledTextField<InputType: Any>: View {
    var title: String
    var appiumTextFieldId: String = "" // make id optional
    @Binding var value: InputType
    @State var textInput: String
    let convertTextToValue: (String) -> InputType

    var body: some View {
        HStack {
            Text(title)
            VStack {
                TextField("", text: $textInput, onCommit: {
                    value = convertTextToValue(textInput)
                })
                .setAppiumId(appiumTextFieldId)
                Divider()
            }
        }
    }
}

// A labeled text field for editing a string
struct LabeledStringTextField: View {
    var title: String
    var appiumTextFieldId: String = "" // make id optional

    @Binding var value: String

    var body: some View {
        LabeledTextField<String>(title: title, appiumTextFieldId: appiumTextFieldId, value: $value, textInput: value) {
            String($0)
        }
    }
}

// A labeled text field for editing a Int
struct LabeledIntTextField: View {
    var title: String
    var appiumTextFieldId: String = "" // make id optional

    @Binding var value: Int

    var body: some View {
        LabeledTextField<Int>(title: title, appiumTextFieldId: appiumTextFieldId, value: $value, textInput: String(value)) {
            Int($0) ?? 0
        }
    }
}

// A labeled text field for editing a TimeInterval
struct LabeledTimeIntervalTextField: View {
    var title: String
    var appiumTextFieldId: String = "" // make id optional

    @Binding var value: TimeInterval

    var body: some View {
        LabeledTextField<TimeInterval>(title: title, appiumTextFieldId: appiumTextFieldId, value: $value, textInput: String(value)) {
            TimeInterval($0) ?? 0.0
        }
    }
}
