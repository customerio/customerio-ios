import CioTracking
import Foundation

/// We want to try and limit singletons so, we pass in a di graph from
/// the top level (MessagingPush class) classes and initialize new instances
/// when functions are called below.
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

internal enum QueueTaskType: String {
    case registerPushToken
    case deletePushToken
}
