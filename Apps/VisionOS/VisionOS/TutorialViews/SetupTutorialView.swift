import CioTracking
import MarkdownUI
import SwiftUI

struct SetupTutorialView: View {
    static let title = ScreenTitleConfig("Initialize CustomerIO")
    @ObservedObject var state = AppState.shared

    let onSuccess: (_ workspaceSettings: WorkspaceSettings) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading) {
                GetSiteIdAndAPIKeyTutorialView()
                HLineView()
                InitilizeTheSDKTutorialView(onSuccess: onSuccess)
            }
        }
        .onAppear {
            state.titleConfig = Self.title
        }
    }
}

struct GetSiteIdAndAPIKeyTutorialView: View {
    var body: some View {
        Markdown {
            """
            Before you can use CustomerIO APIs, you need to initialize the SDK with your
            CustomerIO credentials in order to authenticate subsequent requests from the
            SDK. You will need pair of values: `SiteID` and `ApiKey`.

            To get these values:
            1. Go to [fly.customer.io](https://fly.customer.io/) and login
            2. On the top right corner click on the Settings icon and click the Workspace Settings
            """
        }
        HStack(alignment: .top) {
            Image("GoToWorkspaceSettings")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)

            Image("APIAndCredentialsSettings")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
        }

        Markdown {
            """
            3. Note the `SITE ID` and `API KEY` of your workspace

            *P.s You can learn more about workspaces
            [here](https://customer.io/docs/get-started/create-workspace/)*
            """
        }
    }
}

struct InitilizeTheSDKTutorialView: View {
    @State private var workspaceSettings = AppState.shared.workspaceSettings

    @ObservedObject var state = AppState.shared

    let onSuccess: (_ workspaceSettings: WorkspaceSettings) -> Void

    var body: some View {
        Markdown {
            """
            ### Call CustomerIO.initialize
            To initialize the SDK, you need to call `CustomerIO.initialize` in the `AppDelegate.application(_ ,didFinishLaunchingWithOptions:)` method

            Although this example, we will call it when you hit the **Initialize** button. A call like whet you see in the code snippet.

            ```swift
            \(initializeCodeSnippet(withWorkspaceSettings: workspaceSettings))
            ```
            """
        }
        HStack(alignment: .top) {
            FloatingTitleTextField(title: "Site ID", text: $workspaceSettings.siteId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            FloatingTitleTextField(title: "API Key", text: $workspaceSettings.apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        HStack {
            Text("Datacenter Region")
            Picker("Datacenter Region", selection: $workspaceSettings.region) {
                ForEach(Region.allCases, id: \.self) { region in
                    Text(region.rawValue)
                }
            }

            Spacer()

            Button("Initialize") {
                if !workspaceSettings.isSet() {
                    state.errorMessage = "Please make sure to set the site id and API key values"
                    return
                }
                AppState.shared.workspaceSettings = workspaceSettings
                onSuccess(AppState.shared.workspaceSettings)
            }
        }
    }
}

#Preview {
    CommonLayoutView {
        SetupTutorialView { _ in }
    }
}
