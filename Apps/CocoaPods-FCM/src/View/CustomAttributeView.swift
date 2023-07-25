import CioTracking
import SwiftUI

struct CustomAttributeView: View {
    enum AttributeType: String {
        case profile
        case device
    }

    let attributeType: AttributeType

    private var attributeTypeName: String {
        attributeType.rawValue
    }

    @State private var name: String = ""
    @State private var value: String = ""

    var close: () -> Void

    @State private var nonBlockingMessage: String?

    var body: some View {
        ZStack {
            BackButton {
                close()
            }

            VStack {
                Text("Set Custom \(attributeTypeName.capitalized) Attribute").bold().font(.system(size: 20))

                VStack(spacing: 8) {
                    LabeledStringTextField(title: "Attribute Name", appiumId: "Attribute Name Input", value: $name)
                    LabeledStringTextField(title: "Attribute Value", appiumId: "Attribute Value Input", value: $value)
                }.padding([.vertical], 40)

                ColorButton("Send \(attributeTypeName) attributes") {
                    hideKeyboard() // makes all textfields lose focus so that @State variables are up-to-date with the textfield values.

                    if attributeType == .profile {
                        CustomerIO.shared.profileAttributes = [name: value]
                    }

                    if attributeType == .device {
                        CustomerIO.shared.deviceAttributes = [name: value]
                    }

                    var successMessage = "\(attributeTypeName.capitalized) attribute set"

                    if name.isEmpty || value.isEmpty {
                        successMessage += "\nNote: Empty attribute name or value might result in unexpected behavior with the SDK."
                    }

                    nonBlockingMessage = successMessage
                }.setAppiumId("Set \(attributeTypeName.capitalized) Attribute Button")
            }.padding([.horizontal], 20)
        }.overlay(
            ToastView(message: $nonBlockingMessage)
        ).onAppear {
            // Automatic screen view tracking in the Customer.io SDK does not work with SwiftUI apps (only UIKit apps).
            // Therefore, this is how we can perform manual screen view tracking.
            CustomerIO.shared.screen(name: "Custom\(attributeTypeName.capitalized)Attributes")
        }
    }
}
