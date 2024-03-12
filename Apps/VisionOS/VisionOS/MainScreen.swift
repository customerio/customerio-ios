import CioTracking
import MarkdownUI
import SwiftUI

/**
 This file is the main place for example CustomerIO usage
 Its main objectives are:
 - Basic logic to switch between different view
 - Show all the calls to CustomerIO in one place for simplicity
 */

@ViewBuilder func view(forLink link: InlineNavigationLink) -> some View {
    let state = AppState.shared
    switch link {
    case .sampleAppIntro:
        SampleAppIntro()
    case .install:
        SDKInstallationTutorialView()
    case .setup:
        SetupTutorialView { workspaceSettings in
            CustomerIO.initialize(
                siteId: workspaceSettings.siteId,
                apiKey: workspaceSettings.apiKey,
                region: workspaceSettings.region
            ) { config in

                // Debug config just to make the demo
                // easier. You can learn more about these configs
                // here: https://customer.io/docs/sdk/ios/getting-started/#configuration-options
                config.backgroundQueueMinNumberOfTasks = 1
                config.backgroundQueueSecondsDelay = 0
                config.logLevel = .debug
            }
            state.navigationPath = [.customerIOIntro]
        }

    case .customerIOIntro:
        PostInitializeCustomerIOIntro()

    case .identify:
        IdentifyTutorialView { _ in
            CustomerIO.shared.identify(
                identifier: state.profile.id,
                body: state.profile.properties.toDictionary()
            )
            state.navigationPath = [.howToTestIdentify]
        }
    default:
        Text("Not implemented")
    }
}

// MARK: MainScreen View

struct MainScreen: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        CommonLayoutView {
            NavigationStack(path: $state.navigationPath) {
                view(forLink: state.navigationPath.first ?? .sampleAppIntro)
                    .navigationDestination(for: InlineNavigationLink.self) { link in
                        view(forLink: link)
                            .navigationBarBackButtonHidden()
                        Spacer()
                    }
                Spacer()
            }
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard let link = InlineNavigationLink(fromUrl: url) else {
                        return .systemAction
                    }
                    state.navigationPath = [link]
                    return .handled
                }
            )
        }
    }
}

// MARK: Preview

#Preview(windowStyle: .automatic) {
    MainScreen()
}
