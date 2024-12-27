import CioAnalytics
import CioInternalCommon
/// Plugin to filter screen events based on the configuration provided by customer app.
/// This plugin is used to filter out screen events that should not be processed further.
class ScreenFilterPlugin: EventPlugin {
    private let screenViewUse: ScreenView
    public let type = PluginType.enrichment
    public weak var analytics: Analytics?

    init(screenViewUse: ScreenView) {
        self.screenViewUse = screenViewUse
    }

    func screen(event: ScreenEvent) -> ScreenEvent? {
        // Filter out screen events based on the configuration provided by customer app
        // Using switch statement to enforce exhaustive checking for all possible values of ScreenView
        switch screenViewUse {
        case .all:
            return event
        // Do not send screen events to server if ScreenView is not Analytics
        case .inApp:
            return nil
        }
    }
}
