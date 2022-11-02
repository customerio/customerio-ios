import Common
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingInAppModuleHookProvider: ModuleHookProvider {
    private let siteId: SiteId

    private var diGraph: DIGraph? {
//        DIGraph.getInstance(siteId: siteId)
        // TODO: just like other hook providers. do that.
        nil
    }

    init(siteId: SiteId) {
        self.siteId = siteId
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        MessagingInApp.shared
    }

    var queueRunnerHook: QueueRunnerHook? {
        nil
    }

    var deviceAttributesHook: DeviceAttributesHook? {
        nil
    }

    var screenTrackingHook: ScreenTrackingHook? {
        MessagingInApp.shared
    }
}
