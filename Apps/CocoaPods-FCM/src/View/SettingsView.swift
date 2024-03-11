import CioDataPipelines
import SampleAppsCommon
import SwiftUI
import UIKit

struct SettingsView: View {
    var siteId: String?
    var cdpApiKey: String?

    var done: () -> Void
    private let timer = SwiftUITimer()
    @StateObject private var viewModel = ViewModel()

    @State private var alertMessage: String?

    @EnvironmentObject var userManager: UserManager
    @State private var nonBlockingMessage: String?

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
                    LabeledTimeIntervalTextField(title: "BQ seconds delay:", appiumId: nil, value: $viewModel.settings.flushInterval)
                    LabeledIntTextField(title: "BQ min number tasks:", appiumId: nil, value: $viewModel.settings.flushAt)
                    SettingsToggle(title: "Track screens", appiumId: "Track Screens Toggle", isOn: $viewModel.settings.trackScreens)
                    SettingsToggle(title: "Track device attributes", appiumId: "Track Device Attributes Toggle", isOn: $viewModel.settings.trackDeviceAttributes)
                    SettingsToggle(title: "Debug mode", appiumId: "Debug Mode Toggle", isOn: $viewModel.settings.debugSdkMode)
                }

                ColorButton("Save") {
                    hideKeyboard() // makes all textfields lose focus so that @State variables are up-to-date with the textfield values.

                    guard viewModel.settings.flushInterval > 0 else {
                        alertMessage = "BQ seconds delay must be > 0"
                        return
                    }

                    guard viewModel.settings.flushAt > 0 else {
                        alertMessage = "BQ min number tasks must be > 0"
                        return
                    }

                    guard verifyHost(isCDN: true) else {
                        return
                    }

                    nonBlockingMessage = "Settings saved. This will require an app restart to bring the changes in effect."
                    viewModel.saveSettings()

                    let didChangeSiteId = siteIdBeforeEditingSettings != viewModel.settings.siteId
                    if didChangeSiteId { // if siteid changed, we need to re-identify for the Customer.io SDK to get into a working state.
                        userManager.logout()
                    }
                    timer.start(interval: TimeInterval(3)) {
                        done()
                    }
                }.setAppiumId("Save Settings Button")

                Button("Restore default settings") {
                    viewModel.restoreDefaultSettings()
                }.setAppiumId("Restore Default Settings Button")
            }

            .padding([.leading, .trailing], 10)
            .onAppear {
                siteIdBeforeEditingSettings = BuildEnvironment.CustomerIO.siteId

                // If parameters were passed into this View's constructor, updating the VM now will update the UI.
                if let siteId = siteId {
                    viewModel.settings.siteId = siteId
                }
                if let cdpApiKey = cdpApiKey {
                    viewModel.settings.cdpApiKey = cdpApiKey
                }

                // Automatic screen view tracking in the Customer.io SDK does not work with SwiftUI apps (only UIKit apps).
                // Therefore, this is how we can perform manual screen view tracking.
                CustomerIO.shared.screen(title: "Settings")
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
        .overlay(
            ToastView(message: $nonBlockingMessage)
        )
    }

    private func verifyHost(isCDN: Bool = true) -> Bool {
        var enteredUrl = viewModel.settings.cdnHost
        var hostType = "CDN Host"
        if !isCDN {
            enteredUrl = viewModel.settings.apiHost
            hostType = "API Host"
        }

        if enteredUrl.isEmpty {
            alertMessage = "\(hostType) is empty. Therefore, I cannot save the settings."
            return false
        }

        guard let _ = URL(string: enteredUrl) else {
            alertMessage = "\(hostType), \(enteredUrl), is not a valid URL. Therefore, I cannot save the settings."
            return false
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
            self.pushToken = CustomerIO.shared.registeredDeviceToken ?? "(none)"
            self.settings = settingsManager.appSetSettings ?? CioSettings.getFromCioSdk()
        }

        func saveSettings() {
            settingsManager.appSetSettings = settings
        }

        func restoreDefaultSettings() {
            settingsManager.appSetSettings = nil // remove app overriden settings from device memory

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
