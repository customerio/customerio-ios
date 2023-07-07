import CioTracking
import SwiftUI

struct CustomEventView: View {
    @State private var eventName: String = ""
    @State private var propertyName: String = ""
    @State private var propertyValue: String = ""

    var close: () -> Void
    var done: (_ eventName: String, _ propertyName: String, _ propertyValue: String) -> Void

    @State private var alertMessage: String?

    var body: some View {
        ZStack {
            BackButton {
                close()
            }

            VStack {
                Text("Send Custom Event").bold().font(.system(size: 20))

                VStack(spacing: 8) {
                    LabeledTextField(title: "Event Name", appiumTextFieldId: "Event Name Input", value: $eventName)
                    LabeledTextField(title: "Property Name", appiumTextFieldId: "Property Name Input", value: $propertyName)
                    LabeledTextField(title: "Property Value", appiumTextFieldId: "Property Value Input", value: $propertyValue)
                }.padding([.vertical], 40)

                ColorButton("Send Event") {
                    var alertMessage = "Event sent successfully!"

                    if eventName.isEmpty {
                        alertMessage += "\n\n Note: Empty event name might result in unexpected behavior with the SDK."
                    }

                    self.alertMessage = alertMessage
                }.setAppiumId("Send Event Button")
            }.padding([.horizontal], 20)
                .alert(isPresented: .notNil(alertMessage)) {
                    Alert(
                        title: Text(""),
                        message: Text(alertMessage!),
                        dismissButton: .default(Text("OK")) {
                            done(eventName, propertyName, propertyValue)
                        }
                    )
                }
        }
    }
}
