import CioTracking
import SampleAppsCommon
import SwiftUI

struct SettingsView: View {
    var done: () -> Void

    private let settingsManager = CioSettingsManager()

    @StateObject private var viewModel = ViewModel()

    var body: some View {
        // TODO: add back button in UI to dismiss screen. add appium ID to it.

        VStack(spacing: 5) {
            SettingsTextField(title: "Tracking URL:", value: $viewModel.settings.trackUrl).setAppiumId("Track URL Input")
            SettingsTextField(title: "Site id:", value: $viewModel.settings.siteId).setAppiumId("Site ID Input")
            SettingsTextField(title: "API key:", value: $viewModel.settings.apiKey).setAppiumId("API Key Input")
            SettingsTextField(title: "BQ seconds delay:", value: $viewModel.settings.bqSecondsDelay.toStringBinding())
            SettingsTextField(title: "BQ min number tasks:", value: $viewModel.settings.bqMinNumberTasks.toStringBinding())
            SettingsToggle(title: "Track screens", isOn: $viewModel.settings.trackScreens).setAppiumId("Track Screens Toggle")
            SettingsToggle(title: "Track device attributes", isOn: $viewModel.settings.trackDeviceAttributes).setAppiumId("Track Device Attributes Toggle")
            SettingsToggle(title: "Debug mode", isOn: $viewModel.settings.debugSdkMode).setAppiumId("Debug Mode Toggle")

            ColorButton(title: "Save") {
                // save settings to device storage for app to re-use when app is restarted
                settingsManager.settings = viewModel.settings

                // Re-initialize the SDK to make the config changes go into place immediately
                CustomerIO.initialize(siteId: viewModel.settings.siteId, apiKey: viewModel.settings.apiKey, region: .US) { config in
                    viewModel.settings.configureCioSdk(config: &config)
                }

                done()
            }.setAppiumId("Save Settings Button")

            Button("Restore default settings") {
                settingsManager.restoreSdkDefaultSettings()
            }.setAppiumId("Restore Default Settings Button")
        }
        .padding([.leading, .trailing], 10)
    }

    class ViewModel: ObservableObject {
        @Published var settings: CioSettings = CioSettingsManager().settings
    }
}

struct SettingsTextField: View {
    var title: String

    @Binding var value: String

    var body: some View {
        HStack {
            Text(title)
            TextField("", text: $value)
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
