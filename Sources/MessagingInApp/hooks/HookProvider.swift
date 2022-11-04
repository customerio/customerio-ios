import CioTracking
import Common
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingInAppModuleHookProvider: ModuleHookProvider {
    private let sdkInitializedUtil = SdkInitializedUtilImpl()

    private var siteId: SiteId? {
        diGraph?.siteId
    }

    private var diGraph: DIGraph? {
        sdkInitializedUtil.postInitializedData?.diGraph
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        guard let siteId = siteId, let diGraph = diGraph else { return nil }

        return MessagingInAppImplementation(siteId: siteId, diGraph: diGraph)
    }

    var queueRunnerHook: QueueRunnerHook? {
        nil
    }

    var deviceAttributesHook: DeviceAttributesHook? {
        nil
    }

    var screenTrackingHook: ScreenTrackingHook? {
        guard let siteId = siteId, let diGraph = diGraph else { return nil }

        return MessagingInAppImplementation(siteId: siteId, diGraph: diGraph)
    }
}
