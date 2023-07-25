import CioTracking
import SwiftUI

struct CustomEventView: View {
    @State private var eventName: String = ""
    @State private var propertyName: String = ""
    @State private var propertyValue: String = ""

    var close: () -> Void

    @State private var nonBlockingMessage: String?

    var body: some View {
        ZStack {
            BackButton {
                close()
            }

            VStack {
                Text("Send Custom Event").bold().font(.system(size: 20))

                VStack(spacing: 8) {
                    LabeledStringTextField(title: "Event Name", appiumId: "Event Name Input", value: $eventName)
                    LabeledStringTextField(title: "Property Name", appiumId: "Property Name Input", value: $propertyName)
                    LabeledStringTextField(title: "Property Value", appiumId: "Property Value Input", value: $propertyValue)
                }.padding([.vertical], 40)

                ColorButton("Send Event") {
                    hideKeyboard() // makes all textfields lose focus so that @State variables are up-to-date with the textfield values.

                    CustomerIO.shared.track(name: eventName, data: [propertyName: propertyValue])

                    var successMessage = "Custom event sent"

                    if eventName.isEmpty {
                        successMessage += "\nNote: Empty event name might result in unexpected behavior with the SDK."
                    }

                    nonBlockingMessage = successMessage
                }.setAppiumId("Send Event Button")
            }.padding([.horizontal], 20)
        }.overlay(
            ToastView(message: $nonBlockingMessage)
        ).onAppear {
            // Automatic screen view tracking in the Customer.io SDK does not work with SwiftUI apps (only UIKit apps).
            // Therefore, this is how we can perform manual screen view tracking.
            CustomerIO.shared.screen(name: "CustomEvent")
        }
    }
}
