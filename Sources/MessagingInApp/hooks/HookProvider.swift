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
