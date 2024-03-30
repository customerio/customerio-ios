import MarkdownUI
import SwiftUI

func deviceAttributesCodeSnippet(_ attributes: [Attribute]) -> String {
    
    if attributes.isEmpty {
        return "// enter device attributes"
    } else {
        let attributesStr = propertiesToTutorialString(attributes)
        return
            """
            CustomerIO.shared.deviceAttributes = \(attributesStr)
            """
    }
}

struct DeviceAttributesView: View {
    @ObservedObject var state = AppState.shared

    @State private var attributes: [Attribute] = []

    let onSuccess: (_ deviceAttributes: [Attribute]) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Markdown {
                """
                You can set/update device attributes at any point in your app by setting values in the
                `CustomerIO.shared.deviceAttributes` dictionary.
                If you are interested to learn about how device attributes is being used,
                [click here](https://customer.io/docs/journeys/attributes/#attribute-segment).

                ```swift
                \(deviceAttributesCodeSnippet(attributes))
                ```

                """
            }

            PropertiesInputView(terminology: .attributes, properties: $attributes)

            Button("Set/Update device attribute") {
                onSuccess(attributes)
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
