import Common
import Foundation

class TrackingModuleHookProvider: ModuleHookProvider {
    
    private let sdkInitializedUtil = SdkInitializedUtilImpl()

    private var diGraph: DIGraph? {
        sdkInitializedUtil.postInitializedData?.diGraph
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        nil
    }

    var queueRunnerHook: QueueRunnerHook? {
        diGraph?.queueRunnerHook
    }

    var screenTrackingHook: ScreenTrackingHook? {
        nil
    }
    
    var pushNotificationPromptHook: PushNotificationPromptHook? {
        nil
    }
}
