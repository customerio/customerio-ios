import MarkdownUI
import SwiftUI

private func profileAttributeCodeSnippet(_ attributes: [Attribute]) -> String {
    if attributes.isEmpty {
        return "// enter profile attributes"
    } else {
        let attributesStr = propertiesToTutorialString(attributes)
        return
            """
            CustomerIO.shared.profileAttributes = \(attributesStr)
            """
    }
}

struct ProfileAttributesView: View {
    @ObservedObject var state = AppState.shared

    @State private var attributes: [Attribute] = []

    let onSuccess: (_ profileAttributes: [Attribute]) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Markdown {
                """
                You can set/update user traits at any point in your app by setting values in the
                `CustomerIO.shared.profileAttributes` dictionary.
                [Click here](https://customer.io/docs/journeys/attributes/#attribute-segment) to learn about how profile traits (sometimes called "attributes") are used in Customer.io.

                ```swift
                \(profileAttributeCodeSnippet(attributes))
                ```
                """
            }

            PropertiesInputView(terminology: .attributes, properties: $attributes)

            Button("Set/Update profile attribute") {
                onSuccess(attributes)
            }
        }
    }
}

#Preview {
    MainLayoutView(selectedExample: .constant(.profileAttributes)) {
        ProfileAttributesView { _ in
        }
    }
}
