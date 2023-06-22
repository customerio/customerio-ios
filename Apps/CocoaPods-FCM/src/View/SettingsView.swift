import CioTracking
import SampleAppsCommon
import SwiftUI
import UIKit

struct SettingsView: View {
    var siteId: String?
    var apiKey: String?

    var done: () -> Void

    @StateObject private var viewModel = ViewModel()

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
                    LabeledTextField(title: "Tracking URL:", value: $viewModel.settings.trackUrl).setAppiumId("Track URL Input")
                    LabeledTextField(title: "Site id:", value: $viewModel.settings.siteId).setAppiumId("Site ID Input")
                    LabeledTextField(title: "API key:", value: $viewModel.settings.apiKey).setAppiumId("API Key Input")
                    LabeledTextField(title: "BQ seconds delay:", value: $viewModel.settings.bqSecondsDelay.toStringBinding())
                    LabeledTextField(title: "BQ min number tasks:", value: $viewModel.settings.bqMinNumberTasks.toStringBinding())
                    SettingsToggle(title: "Track screens", isOn: $viewModel.settings.trackScreens).setAppiumId("Track Screens Toggle")
                    SettingsToggle(title: "Track device attributes", isOn: $viewModel.settings.trackDeviceAttributes).setAppiumId("Track Device Attributes Toggle")
                    SettingsToggle(title: "Debug mode", isOn: $viewModel.settings.debugSdkMode).setAppiumId("Debug Mode Toggle")
                }

                ColorButton("Save") {
                    // save settings to device storage for app to re-use when app is restarted
                    viewModel.saveSettings()

                    // Re-initialize the SDK to make the config changes go into place immediately
                    CustomerIO.initialize(siteId: viewModel.settings.siteId, apiKey: viewModel.settings.apiKey, region: .US) { config in
                        viewModel.settings.configureCioSdk(config: &config)
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
        }
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

        func saveSettings() {
            settingsManager.settings = settings
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
