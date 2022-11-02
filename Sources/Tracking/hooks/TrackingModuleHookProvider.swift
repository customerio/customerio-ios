import Common
import Foundation

class TrackingModuleHookProvider: ModuleHookProvider {
    private var diGraph: DIGraph? {
        // TODO: I want to try and reference the di graph in only 1 class.
        // this class might need a refactor?

//        CustomerIO.shared.diGraph
        nil
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        nil
    }

    var queueRunnerHook: QueueRunnerHook? {
        diGraph?.queueRunnerHook
    }

    var deviceAttributesHook: DeviceAttributesHook? {
        nil
    }

    var screenTrackingHook: ScreenTrackingHook? {
        nil
    }
}
