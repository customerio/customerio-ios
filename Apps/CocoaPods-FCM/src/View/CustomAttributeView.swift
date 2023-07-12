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
                    LabeledStringTextField(title: "Attribute Name", appiumId: "Attribute Name Input", value: $name)
                    LabeledStringTextField(title: "Attribute Value", appiumId: "Attribute Value Input", value: $value)
                }.padding([.vertical], 40)

                ColorButton("Send \(attributeTypeName) attributes") {
                    if name.isEmpty || value.isEmpty {
                        alertMessage = "Note: Empty attribute name or value might result in unexpected behavior with the SDK."
                    } else {
                        done(name, value)
                    }
                }.setAppiumId("Set \(attributeTypeName.capitalized) Attribute Button")
            }.padding([.horizontal], 20)
                .alert(isPresented: .notNil(alertMessage)) {
                    Alert(
                        title: Text("\(attributeTypeName.capitalized) attribute set"),
                        message: Text(alertMessage!),
                        dismissButton: .default(Text("OK")) {
                            done(name, value)
                        }
                    )
                }
        }
    }
}
