import CioTracking
import Common
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingPushModuleHookProvider: ModuleHookProvider {
    private let sdkInitializedUtil = SdkInitializedUtilImpl()

    private var diGraph: DIGraph? {
        sdkInitializedUtil.postInitializedData?.diGraph
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        guard let diGraph = diGraph else { return nil }

        return MessagingPushImplementation(diGraph: diGraph)
    }

    var queueRunnerHook: QueueRunnerHook? {
        diGraph?.queueRunnerHook
    }

    var deviceAttributesHook: DeviceAttributesHook? {
        guard let diGraph = diGraph else { return nil }

        return MessagingPushImplementation(diGraph: diGraph)
    }

    var screenTrackingHook: ScreenTrackingHook? {
        nil
    }
}
