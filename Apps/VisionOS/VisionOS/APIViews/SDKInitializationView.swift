import MarkdownUI
import SwiftUI

struct SDKInitializationView: View {
    @EnvironmentObject var viewModel: ViewModel
    @State var workspaceSettings = AppState.shared.workspaceSettings

    let onSuccess: (_ workspaceSettings: WorkspaceSettings) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading) {
                Markdown {
                    """
                    You must have a cdp api key in order to initialize and use the SDK.
                    Click [here](https://customer.io/docs/sdk/ios/quick-start-guide/#prerequisites) to learn more
                    about the prerequisites.

                    ```swift
                    CustomerIO.initialize(withConfig:
                        SDKConfigBuilder(cdpApiKey: "\(workspaceSettings.cdpApiKy)")
                        .build())
                    ```
                    """
                }
                FloatingTitleTextField(title: "CDP API KEY", text: $workspaceSettings.cdpApiKy)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Initialize") {
                    if !workspaceSettings.isSet() {
                        viewModel.errorMessage = "Please make sure to enter the CDP API Key"
                        return
                    }
                    AppState.shared.workspaceSettings = workspaceSettings
                    onSuccess(AppState.shared.workspaceSettings)
                }

                Spacer()
            }
        }
    }
}

#Preview {
    MainLayoutView(selectedExample: .constant(.initialize)) {
        SDKInitializationView { _ in }
    }
}
