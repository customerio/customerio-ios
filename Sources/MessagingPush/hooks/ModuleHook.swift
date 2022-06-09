import Common
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingPushModuleHookProvider: ModuleHookProvider {
    private let siteId: SiteId

    private var diGraph: DIGraph {
        DIGraph.getInstance(siteId: siteId)
    }

    init(siteId: SiteId) {
        self.siteId = siteId
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        MessagingPushImplementation(siteId: siteId)
    }

    var queueRunnerHook: QueueRunnerHook? {
        diGraph.queueRunnerHook
    }

    var deviceAttributesHook: DeviceAttributesHook? {
        MessagingPushImplementation(siteId: siteId)
    }
}
