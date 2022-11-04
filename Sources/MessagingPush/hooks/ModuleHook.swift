import CioTracking
import Common
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingPushModuleHookProvider: ModuleHookProvider {
    private let sdkInitializedUtil = SdkInitializedUtilImpl()

    private var siteId: SiteId? {
        diGraph?.siteId
    }

    private var diGraph: DIGraph? {
        sdkInitializedUtil.postInitializedData?.diGraph
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        guard let siteId = siteId, let diGraph = diGraph else { return nil }

        return MessagingPushImplementation(siteId: siteId, diGraph: diGraph)
    }

    var queueRunnerHook: QueueRunnerHook? {
        diGraph?.queueRunnerHook
    }

    var deviceAttributesHook: DeviceAttributesHook? {
        guard let siteId = siteId, let diGraph = diGraph else { return nil }

        return MessagingPushImplementation(siteId: siteId, diGraph: diGraph)
    }

    var screenTrackingHook: ScreenTrackingHook? {
        nil
    }
}
