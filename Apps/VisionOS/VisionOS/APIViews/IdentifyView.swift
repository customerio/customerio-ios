import MarkdownUI
import Splash
import SwiftUI

private func identifyCodeSnippet(_ profile: Profile) -> String {
    let propertiesStr = propertiesToTutorialString(
        profile.traits,
        linePrefix: "\t\t"
    )

    if !profile.userId.isEmpty, !profile.traits.isEmpty {
        return
            """
            CustomerIO.shared.identify(
                userId: "\(profile.userId)",
                traits: \(propertiesStr)
            )
            """
    } else if !profile.userId.isEmpty {
        return
            """
            CustomerIO.shared.identify(
                userId: "\(profile.userId)"
            )
            """
    } else if !profile.traits.isEmpty {
        return
            """
            CustomerIO.shared.identify(
                traits: \(propertiesStr)
            )
            """
    }
    return "// enter user id or add a trait"
}

struct IdentifyView: View {
    @ObservedObject var state = AppState.shared
    @State private var profile = AppState.shared.profile
    @EnvironmentObject private var viewModel: ViewModel

    let onSuccess: (Profile) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading) {
                Markdown {
                    """
                    If you want to be able to associate events, device or traits to your user, you need to identify this user.
                    Otherwise, any other activities you track will be associated with an annonymouse user.
                    To identify a user, you must set a userId or traits or both.
                    [Learn more](https://customer.io/docs/journeys/identifying-people/#identifiers).

                    ```swift
                    \(identifyCodeSnippet(profile))
                    ```
                    """
                }

                HStack(alignment: .bottom) {
                    FloatingTitleTextField(title: "User ID", text: $profile.userId)
                    Button("Generate UUID") {
                        profile.userId = UUID().uuidString
                    }
                }

                PropertiesInputView(
                    terminology: .traits,
                    showCodableHint: true,
                    properties: $profile.traits
                )

                Divider()
                HStack {
                    Button("Identify") {
                        profile.loggedIn = true
                        if profile.userId.isEmpty, profile.traits.isEmpty {
                            viewModel.errorMessage = "You must set an id or at least one trait"
                            return
                        }
                        state.profile = profile
                        onSuccess(state.profile)
                    }
                }
            }
        }
    }
}

#Preview {
    AppState.shared.profile = Profile.empty()
    return MainLayoutView(selectedExample: .constant(.identify)) {
        IdentifyView { _ in
        }
    }
}
