import MarkdownUI
import Splash
import SwiftUI

private func identifyCodeSnippet(_ profile: Profile) -> String {
    let propertiesStr = propertiesToTutorialString(profile.properties,
    linePrefix: "\t\t")
    if propertiesStr.isEmpty {
        return
"""
CustomerIO.shared.identify(
    identifier: "\(profile.id)"
)
"""
    } else {
        return
"""
CustomerIO.shared.identify(
    identifier: "\(profile.id)",
    data: \(propertiesStr)
)
"""
    }
}

struct IdentifyTutorialView: View {
    @ObservedObject var state = AppState.shared
    @State private var profile = AppState.shared.profile
    @EnvironmentObject private var viewModel: ViewModel
    
    static let title = ScreenTitleConfig("Identify")

    let onSuccess: (Profile) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading) {
                Markdown {
"""
In CustomerIO many things revolve around People. What actions
(tracked events) they do, what we know about them (their attributes),
what devices they use and what are the capabilities of thess devices
(device attributes). All starts with by **Identify**ing the customer.
Learn more about [identifying people](https://customer.io/docs/journeys/identifying-people/#identifiers)

```swift
\(identifyCodeSnippet(profile))
```

`identifier` is the only mandatory parameter. However,
you can also add any encodable data. Use the input below to add
key/value pairs. Try it with a property name `email` and any value.
"Email" is another way you can use to identify people in Customer.io.

"""
                }

                PropertiesInputView(
                    properties: $profile.properties,
                    addPropertiesLabel: "Fill the name and value for a property and tap the **+** button to add a property before calling `Customer.shared.identify`"
                )

                Divider()
                HStack {
                    Button("Identify") {
                        profile.loggedIn = true
                        state.profile = profile
                        onSuccess(state.profile)
                    }
                }
            }
            .onAppear {
                viewModel.titleConfig = Self.title
        }
        }
    }
}

// MARK: Utilities

#Preview {
    AppState.shared.profile = Profile.empty()
    return CommonLayoutView {
        IdentifyTutorialView { _ in
        }
    }
}
