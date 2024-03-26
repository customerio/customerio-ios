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
                Using CustomerIO you can track any events. If there is an identified user, these events will be
                attributed to them or to an annonymouse user otherwise.
                An event must have a name.
                
                Optionally, you can add any properties payload to the event as long
                as the payload type conforms to the Codable protocol.
                [Learn more](https://customer.io/docs/sdk/ios/tracking/track-events/)

                ```swift
                \(eventAsCodeSnippet(event))
                ```
                """
            }

            FloatingTitleTextField(title: "Event name", text: $event.name)

            PropertiesInputView(
                terminology: .properties,
                properties: $event.properties
            )

            Button("Send event") {
                if event.name.isEmpty {
                    viewModel.errorMessage = "Please enter an event name"
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
