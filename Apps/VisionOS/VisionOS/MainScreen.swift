import CioDataPipelines
import MarkdownUI
import SwiftUI

// MARK: MainScreen View

/**
 This file is the main place for example CustomerIO usage
 Its main objectives are:
 - Basic logic to switch between different view
 - Show all the calls to CustomerIO in one place for simplicity
 */
private func getFirstScreen() -> CIOExample {
    let state = AppState.shared
    if state.workspaceSettings.isSet(), state.profile.loggedIn {
        return CIOExample.track
    } else if state.workspaceSettings.isSet() {
        return CIOExample.identify
    }
    return CIOExample.initialize
}

struct MainScreen: View {
    @ObservedObject var state: AppState = .shared
    @EnvironmentObject private var viewModel: ViewModel

    @State var selectedExample = getFirstScreen()
    var body: some View {
        MainLayoutView(selectedExample: $selectedExample) {
            switch selectedExample {
            case .initialize:
                SDKInitializationView { workspaceSettings in
                    CustomerIO.initialize(
                        withConfig:
                        SDKConfigBuilder(cdpApiKey: workspaceSettings.cdpApiKy)
                            .logLevel(.debug)
                            .build())

                    viewModel.successMessage = "SDK Initialized. You can now identify the user"
                    selectedExample = .identify
                }
            case .identify:
                IdentifyView { profile in
                    if !profile.userId.isEmpty, !profile.traits.isEmpty {
                        CustomerIO.shared.identify(userId: profile.userId, traits: profile.traits.toDictionary())
                    }
                    if !profile.userId.isEmpty {
                        CustomerIO.shared.identify(userId: profile.userId)
                    } else {
                        CustomerIO.shared.identify(traits: profile.traits.toDictionary())
                    }

                    viewModel.successMessage = "Any subsequent activities will be attributed to the identified profile"

                    // For debug purpose only
                    CustomerIO.shared.flush()
                }
            case .track:
                TrackEventsView { event in
                    CustomerIO.shared.track(
                        name: event.name,
                        properties: event.properties.toDictionary()
                    )

                    viewModel.successMessage = "Track API has been executed successfully"
                    // For debug purpose only
                    CustomerIO.shared.flush()
                }
            case .profileAttributes:
                ProfileAttributesView { attributes in
                    CustomerIO.shared.profileAttributes = attributes.toDictionary()
                    viewModel.successMessage = "Profile attributes set successfully"
                    // For debug purpose only
                    CustomerIO.shared.flush()
                }
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    MainScreen()
}
