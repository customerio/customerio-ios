import CioTracking
import SampleAppsCommon
import SwiftUI
import UIKit

struct SettingsView: View {
    var siteId: String?
    var apiKey: String?

    var done: () -> Void

    @StateObject private var viewModel = ViewModel()

    @State private var alertMessage: String?

    @EnvironmentObject var userManager: UserManager

    var body: some View {
        ZStack {
            BackButton {
                done()
            }

            VStack(spacing: 5) {
                HStack {
                    Text("Device token: ")
                    OneLineText(viewModel.pushToken)
                    Button(action: {
                        UIPasteboard.general.string = viewModel.pushToken
                    }) {
                        Image(systemName: "list.clipboard.fill").font(.system(size: 24))
                    }
                }

                Group {
                    LabeledStringTextField(title: "Tracking URL:", value: $viewModel.settings.trackUrl)
                        .autocapitalization(.none)
                        .setAppiumId("Track URL Input")
                    LabeledStringTextField(title: "Site id:", value: $viewModel.settings.siteId).setAppiumId("Site ID Input")
                    LabeledStringTextField(title: "API key:", value: $viewModel.settings.apiKey).setAppiumId("API Key Input")
                    LabeledTimeIntervalTextField(title: "BQ seconds delay:", value: $viewModel.settings.bqSecondsDelay)
                    LabeledIntTextField(title: "BQ min number tasks:", value: $viewModel.settings.bqMinNumberTasks)
                    SettingsToggle(title: "Track screens", isOn: $viewModel.settings.trackScreens).setAppiumId("Track Screens Toggle")
                    SettingsToggle(title: "Track device attributes", isOn: $viewModel.settings.trackDeviceAttributes).setAppiumId("Track Device Attributes Toggle")
                    SettingsToggle(title: "Debug mode", isOn: $viewModel.settings.debugSdkMode).setAppiumId("Debug Mode Toggle")
                }

                ColorButton("Save") {
                    guard verifyTrackUrl() else {
                        return
                    }

                    // save settings to device storage for app to re-use when app is restarted
                    let didChangeSiteId = viewModel.saveSettings()

                    // Re-initialize the SDK to make the config changes go into place immediately
                    CustomerIO.initialize(siteId: viewModel.settings.siteId, apiKey: viewModel.settings.apiKey, region: .US) { config in
                        viewModel.settings.configureCioSdk(config: &config)
                    }

                    if didChangeSiteId { // if siteid changed, we need to re-identify for the Customer.io SDK to get into a working state.
                        userManager.logout()
                    }

                    done()
                }.setAppiumId("Save Settings Button")

                Button("Restore default settings") {
                    viewModel.restoreDefaultSettings()
                }.setAppiumId("Restore Default Settings Button")
            }
            .padding([.leading, .trailing], 10)
            .onAppear {
                if let siteId = siteId {
                    viewModel.settings.siteId = siteId
                }
                if let apiKey = apiKey {
                    viewModel.settings.apiKey = apiKey
                }
            }
            .alert(isPresented: .notNil(alertMessage)) {
                Alert(
                    title: Text("Error"),
                    message: Text(alertMessage!),
                    dismissButton: .default(Text("OK")) {
                        alertMessage = nil
                    }
                )
            }
        }
    }

    private func verifyTrackUrl() -> Bool {
        let enteredUrl = viewModel.settings.trackUrl

        guard !enteredUrl.isEmpty else {
            alertMessage = "Tracking URL is empty. Therefore, I cannot save the settings."
            return false
        }

        guard let url = URL(string: enteredUrl) else {
            alertMessage = "Tracking URL, \(enteredUrl), is not a valid URL. Therefore, I cannot save the settings."
            return false
        }

        guard url.scheme != nil, url.scheme == "https" || url.scheme == "http" else {
            alertMessage = "Tracking URL, \(enteredUrl), does not start with https or http. Therefore, I cannot save the settings."
            return false
        }

        guard url.host != nil, !url.host!.isEmpty else {
            alertMessage = "Tracking URL, \(enteredUrl), does not contain a domain name. Therefore, I cannot save the settings."
            return false
        }

        // Auto-fix this instead of making the user fix it.
        let urlEndsWithTrailingSlash = url.absoluteString.hasSuffix("/")
        if !urlEndsWithTrailingSlash {
            viewModel.settings.trackUrl += "/"
        }

        return true
    }

    class ViewModel: ObservableObject {
        @Published var settings: CioSettings
        @Published var pushToken: String

        private let settingsManager: CioSettingsManager
        private let keyValueStorage: KeyValueStore

        init() {
            self.settingsManager = CioSettingsManager()
            self.keyValueStorage = KeyValueStore()
            self.pushToken = keyValueStorage.pushToken ?? "(none)"
            self.settings = settingsManager.settings
        }

        func saveSettings() -> Bool {
            let currentlySetSiteId = CustomerIO.shared.config?.siteId
            let changedSiteId = currentlySetSiteId != settings.siteId

            settingsManager.settings = settings

            return changedSiteId
        }

        func restoreDefaultSettings() {
            settingsManager.restoreSdkDefaultSettings()
            settings = settingsManager.settings
        }
    }
}

struct SettingsToggle: View {
    var title: String

    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Toggle("", isOn: $isOn)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView {}
    }
}
