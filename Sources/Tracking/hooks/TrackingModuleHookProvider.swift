import Common
import Foundation

class TrackingModuleHookProvider: ModuleHookProvider {
    private let siteId: SiteId

    private var diGraphTracking: DITracking {
        DITracking.getInstance(siteId: siteId)
    }

    init(siteId: SiteId) {
        self.siteId = siteId
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        nil
    }

    var queueRunnerHook: QueueRunnerHook? {
        diGraphTracking.queueRunnerHook
    }

    var deviceAttributesHook: DeviceAttributesHook? {
        nil
    }
}
