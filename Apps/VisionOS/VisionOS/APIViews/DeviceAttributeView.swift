import MarkdownUI
import SwiftUI

func deviceAttributeCodeSnippet(_ attribute: Attribute) -> String {
    if attribute.key.isEmpty || attribute.value.isEmpty {
        return "// enter both key and values"
    } else {
        return
            """
            CustomerIO.shared.deviceAttributes["\(attribute.key)"] = "\(attribute.value)"
            """
    }
}

struct DeviceAttributesView: View {
    @ObservedObject var state = AppState.shared

    @State private var attribute = Attribute(key: "", value: "")

    let onSuccess: (_ profileAttribute: Attribute) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Markdown {
                """
                You can set/update device attributes at any point in your app by setting values in the
                `CustomerIO.shared.deviceAttributes` dictionary.
                If you are interested to learn about hos profile attributes is being used,
                [click here](https://customer.io/docs/journeys/attributes/#attribute-segment).

                ```swift
                \(deviceAttributeCodeSnippet(attribute))
                ```

                """
            }

            HStack(alignment: .bottom) {
                FloatingTitleTextField(
                    title: "Attribute name",
                    text: $attribute.key
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                FloatingTitleTextField(
                    title: "Attribute value",
                    text: $attribute.value
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Button("Set/Update device attribute") {
                onSuccess(attribute)
            }
        }
    }
}

#Preview {
    MainLayoutView(selectedExample: .constant(.deviceAttributes)) {
        DeviceAttributesView { _ in
        }
    }
}
