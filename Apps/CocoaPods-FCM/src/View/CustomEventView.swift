import CioTracking
import SwiftUI

struct CustomEventView: View {
    @State private var eventName: String = ""
    @State private var propertyName: String = ""
    @State private var propertyValue: String = ""

    var done: (_ eventName: String, _ propertyName: String, _ propertyValue: String) -> Void

    @State private var showConfirmationAlert: Bool = false

    var body: some View {
        VStack {
            Text("Send Custom Event").bold().font(.system(size: 20))

            VStack(spacing: 8) {
                LabeledTextField(title: "Event Name", appiumTextFieldId: "Event Name Input", value: $eventName)
                LabeledTextField(title: "Property Name", appiumTextFieldId: "Property Name Input", value: $propertyName)
                LabeledTextField(title: "Property Value", appiumTextFieldId: "Property Value Input", value: $propertyValue)
            }.padding([.vertical], 40)

            ColorButton("Send Event") {
                showConfirmationAlert = true
            }.setAppiumId("Send Event Button")
        }.padding([.horizontal], 20)
            .alert(isPresented: $showConfirmationAlert) {
                Alert(
                    title: Text(""),
                    message: Text("Event sent successfully"),
                    dismissButton: .default(Text("OK")) {
                        done(eventName, propertyName, propertyValue)
                    }
                )
            }
    }
}
