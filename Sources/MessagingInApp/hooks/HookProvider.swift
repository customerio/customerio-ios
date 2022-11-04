import CioTracking
import Common
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingInAppModuleHookProvider: ModuleHookProvider {
    private let siteId: SiteId

    private let sdkInitializedUtil = SdkInitializedUtilImpl()

    private var diGraph: DIGraph? {
        sdkInitializedUtil.postInitializedData?.diGraph
    }

    init(siteId: SiteId) {
        self.siteId = siteId
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        MessagingInAppImplementation(siteId: siteId, diGraph: diGraph!)
    }

    var queueRunnerHook: QueueRunnerHook? {
        nil
    }

    var deviceAttributesHook: DeviceAttributesHook? {
        nil
    }

    var screenTrackingHook: ScreenTrackingHook? {
        MessagingInAppImplementation(siteId: siteId, diGraph: diGraph!)
    }
}
