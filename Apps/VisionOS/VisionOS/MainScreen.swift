import CioDataPipelines
import MarkdownUI
import SwiftUI

/**
 This file is the main place for example CustomerIO usage
 Its main objectives are:
 - Basic logic to switch between different view
 - Show all the calls to CustomerIO in one place for simplicity
 */

// MARK: MainScreen View

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
                Text("Identify")
            case .track:
                Text("Track")
            case .profileAttributes:
                Text("Profile Attribute")
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    MainScreen()
}
