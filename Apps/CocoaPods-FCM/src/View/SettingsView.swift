import CioDataPipelines
import SampleAppsCommon
import SwiftUI
import UIKit

struct SettingsView: View {
    var siteId: String?
    var cdpApiKey: String?

    var done: () -> Void

    @StateObject private var viewModel = ViewModel()

    @State private var alertMessage: String?

    @EnvironmentObject var userManager: UserManager

    @State private var siteIdBeforeEditingSettings: String = ""

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
                    LabeledStringTextField(title: "CDN Host:", appiumId: "CDN Host Input", value: $viewModel.settings.cdnHost)
                        .autocapitalization(.none)
                    LabeledStringTextField(title: "API Host:", appiumId: "API Host Input", value: $viewModel.settings.apiHost)
                        .autocapitalization(.none)
                    LabeledStringTextField(title: "Site id:", appiumId: "Site ID Input", value: $viewModel.settings.siteId)
                    LabeledStringTextField(title: "CDP API key:", appiumId: "CDP API Key Input", value: $viewModel.settings.cdpApiKey)
                    LabeledTimeIntervalTextField(title: "BQ seconds delay:", appiumId: nil, value: $viewModel.settings.bqSecondsDelay)
                    LabeledIntTextField(title: "BQ min number tasks:", appiumId: nil, value: $viewModel.settings.bqMinNumberTasks)
                    SettingsToggle(title: "Track screens", appiumId: "Track Screens Toggle", isOn: $viewModel.settings.trackScreens)
                    SettingsToggle(title: "Track device attributes", appiumId: "Track Device Attributes Toggle", isOn: $viewModel.settings.trackDeviceAttributes)
                    SettingsToggle(title: "Debug mode", appiumId: "Debug Mode Toggle", isOn: $viewModel.settings.debugSdkMode)
                }

                ColorButton("Save") {
                    hideKeyboard() // makes all textfields lose focus so that @State variables are up-to-date with the textfield values.

                    guard viewModel.settings.bqSecondsDelay > 0 else {
                        alertMessage = "BQ seconds delay must be > 0"
                        return
                    }

                    guard viewModel.settings.bqMinNumberTasks > 0 else {
                        alertMessage = "BQ min number tasks must be > 0"
                        return
                    }

                    guard verifyHost(isCDN: true) else {
                        return
                    }

                    viewModel.saveSettings()

                    // TODO: Make initialising consistent with other sample apps

                    // Re-initialize the SDK to make the config changes go into place immediately
//                    CustomerIO.initialize(siteId: viewModel.settings.siteId, apiKey: viewModel.settings.apiKey, region: .US) { config in
//                        viewModel.settings.configureCioSdk(config: &config)
//                    }

                    let didChangeSiteId = siteIdBeforeEditingSettings != viewModel.settings.siteId
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
                siteIdBeforeEditingSettings = CustomerIO.shared.siteId!

                // If parameters were passed into this View's constructor, updating the VM now will update the UI.
                if let siteId = siteId {
                    viewModel.settings.siteId = siteId
                }
                if let cdpApiKey = cdpApiKey {
                    viewModel.settings?.cdpApiKey = cdpApiKey
                }

                // Automatic screen view tracking in the Customer.io SDK does not work with SwiftUI apps (only UIKit apps).
                // Therefore, this is how we can perform manual screen view tracking.
                CustomerIO.shared.screen(name: "Settings")
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

    private func verifyHost(isCDN: Bool = true) -> Bool {
        var enteredUrl = viewModel.settings?.cdnHost
        var hostType = "CDN Host"
        if !isCDN {
            enteredUrl = viewModel.settings?.apiHost
            hostType = "API Host"
        }

        guard let enteredUrl = enteredUrl else {
            alertMessage = "\(hostType) not found. Therefore, I cannot save the settings."
            return false
        }
        guard !enteredUrl.isEmpty else {
            alertMessage = "\(hostType) is empty. Therefore, I cannot save the settings."
            return false
        }

        guard let url = URL(string: enteredUrl) else {
            alertMessage = "\(hostType), \(enteredUrl), is not a valid URL. Therefore, I cannot save the settings."
            return false
        }

        // TODO: Verify if this is required
        guard url.host != nil, !url.host!.isEmpty else {
            alertMessage = "\(hostType), \(enteredUrl), does not contain a domain name. Therefore, I cannot save the settings."
            return false
        }

        return true
    }

    class ViewModel: ObservableObject {
        @Published var settings: CioSettings?
        @Published var pushToken: String

        private let settingsManager: CioSettingsManager
        private let keyValueStorage: KeyValueStore

        init() {
            self.settingsManager = CioSettingsManager()
            self.keyValueStorage = KeyValueStore()
            self.pushToken = CustomerIO.shared.registeredDeviceToken ?? "(none)"
            self.settings = settingsManager.appSetSettings ?? CioSettings.getFromCioSdk()
        }

        func saveSettings() {
            settingsManager.appSetSettings = settings
        }

        func restoreDefaultSettings() {
            settingsManager.appSetSettings = nil // remove app overriden settings from device memory

            // TODO: Make initialising consistent with other sample apps
            // restore the siteid and apikey used at compile-time as defaults.
            // Do this before reading the app settings from the SDK so that the correct siteid and apikey are read.
//            CustomerIO.initialize(siteId: BuildEnvironment.CustomerIO.siteId, apiKey: BuildEnvironment.CustomerIO.apiKey, region: .US) { _ in }

            settings = CioSettings.getFromCioSdk() // Now that the SDK has default configuration back, refresh UI
        }
    }
}

struct SettingsToggle: View {
    let title: String
    let appiumId: String?

    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Toggle("", isOn: $isOn).setAppiumId(appiumId)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView {}
    }
}
