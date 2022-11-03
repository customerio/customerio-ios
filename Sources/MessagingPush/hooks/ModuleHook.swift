import CioTracking
import Common
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingPushModuleHookProvider: ModuleHookProvider {
    private let siteId: SiteId

    private let sdkInitializedUtil = SdkInitializedUtilImpl()

    private var diGraph: DIGraph? {
        sdkInitializedUtil.postInitializedData?.diGraph
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
