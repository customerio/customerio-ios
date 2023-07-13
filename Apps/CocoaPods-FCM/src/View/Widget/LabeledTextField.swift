import Foundation
import SwiftUI

// A TextField with a label on the left side.
// Accepts many different types of data.
struct LabeledTextField<InputType: Equatable>: View {
    let title: String
    let appiumId: String?
    @Binding var value: InputType
    let textToValue: (String) -> InputType
    let valueToText: (InputType) -> String

    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(title)
            VStack {
                TextField("", text: $text, onEditingChanged: { focused in
                    if !focused { // when textfield loses focus
                        value = textToValue(text)
                    }
                }, onCommit: { // when return key on keyboard pressed
                    value = textToValue(text)
                })
                .setAppiumId(appiumId)
                Divider()
            }
        }.onChange(of: value) { newValue in // If the value changes outside of this View, update the text that the TextField is displaying in the UI.
            text = valueToText(newValue)
        }.onAppear {
            text = valueToText(value)
        }
    }
}

// A labeled text field for editing a string
struct LabeledStringTextField: View {
    let title: String
    let appiumId: String?

    @Binding var value: String

    var body: some View {
        LabeledTextField<String>(title: title, appiumId: appiumId, value: $value, textToValue: { $0 }, valueToText: { $0 })
    }
}

// A labeled text field for editing a Int
struct LabeledIntTextField: View {
    let title: String
    let appiumId: String?

    @Binding var value: Int

    var body: some View {
        LabeledTextField<Int>(title: title, appiumId: appiumId, value: $value, textToValue: { Int($0) ?? 0 }, valueToText: { String($0) })
    }
}

// A labeled text field for editing a TimeInterval
struct LabeledTimeIntervalTextField: View {
    let title: String
    let appiumId: String?

    @Binding var value: TimeInterval

    var body: some View {
        LabeledTextField<TimeInterval>(title: title, appiumId: appiumId, value: $value, textToValue: { TimeInterval($0) ?? 0 }, valueToText: { String($0) })
    }
}
