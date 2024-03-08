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
    switch link {
    case .sampleAppIntro:
        SampleAppIntro()
    case .install:
        SDKInstallationTutorialView()
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
                    withAnimation {
                        state.navigationPath = [link]
                    }
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
