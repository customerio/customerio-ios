import CioInternalCommon
import CioTracking
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingInAppModuleHookProvider: ModuleHookProvider {
    private let sdkInitializedUtil = SdkInitializedUtilImpl()

    private var diGraph: DIGraph? {
        sdkInitializedUtil.postInitializedData?.diGraph
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        guard let diGraph = diGraph else { return nil }

        return MessagingInAppImplementation(diGraph: diGraph)
    }

    var queueRunnerHook: QueueRunnerHook? {
        nil
    }

    var screenTrackingHook: ScreenTrackingHook? {
        guard let diGraph = diGraph else { return nil }

        return MessagingInAppImplementation(diGraph: diGraph)
    }
}
