import CioTracking
import SwiftUI

struct CustomAttributeView: View {
    enum AttributeType {
        case profileAttributes
        case deviceAttributes
    }

    let attributeType: AttributeType

    private var headerText: String {
        switch attributeType {
        case .profileAttributes: return "Set Custom Profile Attribute"
        case .deviceAttributes: return "Set Custom Device Attribute"
        }
    }

    private var buttonText: String {
        switch attributeType {
        case .profileAttributes: return "Send profile attributes"
        case .deviceAttributes: return "Send device attributes"
        }
    }

    private var alertMessage: String {
        switch attributeType {
        case .profileAttributes: return "Profile attribute sent successfully!"
        case .deviceAttributes: return "Device attribute sent successfully!"
        }
    }

    private var appiumButtonText: String {
        switch attributeType {
        case .profileAttributes: return "Set Profile Attribute Button"
        case .deviceAttributes: return "Set Device Attribute Button"
        }
    }

    @State private var name: String = ""
    @State private var value: String = ""

    var close: () -> Void
    var done: (_ name: String, _ value: String) -> Void

    @State private var showConfirmationAlert: Bool = false

    var body: some View {
        ZStack {
            BackButton {
                close()
            }

            VStack {
                Text(headerText).bold().font(.system(size: 20))

                VStack(spacing: 8) {
                    LabeledTextField(title: "Attribute Name", appiumTextFieldId: "Attribute Name Input", value: $name)
                    LabeledTextField(title: "Attribute Value", appiumTextFieldId: "Attribute Value Input", value: $value)
                }.padding([.vertical], 40)

                ColorButton(buttonText) {
                    showConfirmationAlert = true
                }.setAppiumId(appiumButtonText)
            }.padding([.horizontal], 20)
                .alert(isPresented: $showConfirmationAlert) {
                    Alert(
                        title: Text(""),
                        message: Text(alertMessage),
                        dismissButton: .default(Text("OK")) {
                            done(name, value)
                        }
                    )
                }
        }
    }
}
