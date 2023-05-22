import CioTracking
import SampleAppsCommon
import SwiftUI

struct SettingsView: View {
    var done: () -> Void

    private let settingsManager = CioSettingsManager()

    @StateObject private var viewModel = ViewModel()

    var body: some View {
        VStack(spacing: 5) {
            SettingsTextField(title: "Tracking URL:", value: $viewModel.settings.trackUrl)
            SettingsTextField(title: "Site id:", value: $viewModel.settings.siteId)
            SettingsTextField(title: "API key:", value: $viewModel.settings.apiKey)
            SettingsTextField(title: "BQ seconds delay:", value: $viewModel.settings.bqSecondsDelay.toStringBinding())
            SettingsTextField(title: "BQ min number tasks:", value: $viewModel.settings.bqMinNumberTasks.toStringBinding())
            SettingsToggle(title: "Track screens", isOn: $viewModel.settings.trackScreens)
            SettingsToggle(title: "Track device attributes", isOn: $viewModel.settings.trackDeviceAttributes)

            ColorButton(title: "Save") {
                // save settings to device storage for app to re-use when app is restarted
                settingsManager.settings = viewModel.settings

                // Re-initialize the SDK to make the config changes go into place immediately
                CustomerIO.initialize(siteId: viewModel.settings.siteId, apiKey: viewModel.settings.apiKey, region: .US) { config in
                    viewModel.settings.configureCioSdk(config: &config)
                }

                done()
            }
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
