import Common
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingPushModuleHookProvider: ModuleHookProvider {
    private let siteId: SiteId

    private var diGraph: DIGraph? {
        // TODO: like other providers
//        DIGraph.getInstance(siteId: siteId)
        nil
    }

    init(siteId: SiteId) {
        self.siteId = siteId
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        MessagingPushImplementation(siteId: siteId, diGraph: diGraph!)
    }

    var queueRunnerHook: QueueRunnerHook? {
        diGraph?.queueRunnerHook
    }

    var deviceAttributesHook: DeviceAttributesHook? {
        MessagingPushImplementation(siteId: siteId, diGraph: diGraph!)
    }

    var screenTrackingHook: ScreenTrackingHook? {
        nil
    }
}
