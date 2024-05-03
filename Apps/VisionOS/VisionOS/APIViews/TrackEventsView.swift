import MarkdownUI
import SwiftUI

private func eventAsCodeSnippet(_ event: Event) -> String {
    let propertiesStr = propertiesToTutorialString(
        event.properties,
        linePrefix: "\t\t"
    )

    if !event.name.isEmpty, !propertiesStr.isEmpty {
        return
            """
            CustomerIO.shared.track(
                name: "\(event.name)",
                properties: \(propertiesStr)
            )
            """
    } else if !event.name.isEmpty {
        return
            """
            CustomerIO.shared.track(
                name: "\(event.name)"
            )
            """
    }
    return "// enter event name"
}

struct TrackEventsView: View {
    @EnvironmentObject private var viewModel: ViewModel

    @State private var event = Event(name: "", properties: [])

    let onSuccess: (_ event: Event) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Markdown {
                """
                You can track the events your users perform in your app. If you have already identified the user, these events are attributed with the identified user. Otherwise, events are attributed to an anonymous user.
                An event must have a name.

                You can also add relevant properties to the event payload as long
                as the payload type conforms to the Codable protocol.
                [Learn more](https://customer.io/docs/sdk/ios/tracking/track-events/)

                ```swift
                \(eventAsCodeSnippet(event))
                ```
                """
            }

            FloatingTitleTextField(title: "Event name", text: $event.name)
                .textInputAutocapitalization(.never)
            PropertiesInputView(
                terminology: .properties,
                properties: $event.properties
            )

            Button("Send event") {
                if event.name.isEmpty {
                    viewModel.errorMessage = "You must enter an event name"
                    return
                }
                onSuccess(event)
            }
        }
    }
}

#Preview {
    MainLayoutView(selectedExample: .constant(.track)) {
        TrackEventsView { _ in
        }
    }
}
