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
    var done: (_ name: String, _ value: String) -> Void

    @State private var alertMessage: String?

    var body: some View {
        ZStack {
            BackButton {
                close()
            }

            VStack {
                Text("Set Custom \(attributeTypeName.capitalized) Attribute").bold().font(.system(size: 20))

                VStack(spacing: 8) {
                    LabeledTextField(title: "Attribute Name", appiumTextFieldId: "Attribute Name Input", value: $name)
                    LabeledTextField(title: "Attribute Value", appiumTextFieldId: "Attribute Value Input", value: $value)
                }.padding([.vertical], 40)

                ColorButton("Send \(attributeTypeName) attributes") {
                    var alertMessage = "\(attributeTypeName.capitalized) attribute sent successfully!"

                    if name.isEmpty || value.isEmpty {
                        alertMessage += "\n\n Note: Empty attribute name or value might result in expected behavior with the SDK."
                    }

                    self.alertMessage = alertMessage
                }.setAppiumId("Set \(attributeTypeName.capitalized) Attribute Button")
            }.padding([.horizontal], 20)
                .alert(isPresented: .notNil(alertMessage)) {
                    Alert(
                        title: Text(""),
                        message: Text(alertMessage!),
                        dismissButton: .default(Text("OK")) {
                            done(name, value)
                        }
                    )
                }
        }
    }
}
