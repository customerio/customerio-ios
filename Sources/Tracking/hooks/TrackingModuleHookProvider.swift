import Common
import Foundation

class TrackingModuleHookProvider: ModuleHookProvider {
    private let siteId: SiteId

    private var diGraph: DIGraph {
        DIGraph.getInstance(siteId: siteId)
    }

    init(siteId: SiteId) {
        self.siteId = siteId
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        nil
    }

    var queueRunnerHook: QueueRunnerHook? {
        diGraph.queueRunnerHook
    }

    var deviceAttributesHook: DeviceAttributesHook? {
        nil
    }

    var screenTrackingHook: ScreenTrackingHook? {
        nil
    }
}
