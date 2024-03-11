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

struct MainScreen: View {
    @ObservedObject var state: AppState = .shared
    @State var selectedExample = CIOExample.initialize
    var body: some View {
        MainLayoutView(selectedExample: $selectedExample) {
            switch selectedExample {
            case .initialize:
                SDKInitializationView { workspaceSettings in
                    CustomerIO.initialize(
                        withConfig:
                        SDKConfigBuilder(cdpApiKey: workspaceSettings.cdpApiKy)
                            .region(workspaceSettings.region)
                            .logLevel(.debug)
                            .build())
                }
            case .identify:
                Text("Identify")
            case .track:
                Text("Track")
            case .profileAttributes:
                Text("Profile Attribute")
            case .deviceAttributes:
                Text("Device Attributes")
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    MainScreen()
}
