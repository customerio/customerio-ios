import CioTracking
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingPushModuleHookProvider: ModuleHookProvider {
    private let siteId: SiteId

    private var diGraph: DITracking {
        DITracking.getInstance(siteId: siteId)
    }

    private var diGraphMessaging: DIMessagingPush {
        DIMessagingPush.getInstance(siteId: siteId)
    }

    init(siteId: SiteId) {
        self.siteId = siteId
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        diGraphMessaging.pushDeviceTokenRepository as? CioPushDeviceTokenRepository
    }

    var queueRunnerHook: QueueRunnerHook? {
        diGraphMessaging.queueRunnerHook
    }
}
