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

@ViewBuilder
private func eventInputView(_ event: Binding<Event>) -> some View {
    FloatingTitleTextField(title: "Event name", text: event.name)
        .textInputAutocapitalization(.never)
    PropertiesInputView(
        terminology: .properties,
        properties: event.properties
    )
}

struct TrackEventsView: View {
    @EnvironmentObject private var viewModel: ViewModel
    
    @State private var usePushEvent = false

    @State private var event = Event(name: "", properties: [])
    @State private var pushEvent = Event(name: "push", properties: [
        Property(key: "title", value: "Push title!"),
        Property(key: "content", value: "The nicely customized push title")
    ])

    let onSuccess: (_ event: Event) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(isOn: $usePushEvent, label: {
                Text("Push event?")
                    .font(.largeTitle)
            })
            Markdown {
                """
                Using CustomerIO you can track any events. If there is an identified user, these events will be
                attributed to them or to an annonymouse user otherwise.
                An event must have a name.

                Optionally, you can add any properties payload to the event as long
                as the payload type conforms to the Codable protocol.
                [Learn more](https://customer.io/docs/sdk/ios/tracking/track-events/)

                ```swift
                \(eventAsCodeSnippet(usePushEvent ? pushEvent : event))
                ```
                """
            }

            eventInputView(usePushEvent ? $pushEvent : $event)

            Button("Send event") {
                let event = usePushEvent ? pushEvent : event
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
