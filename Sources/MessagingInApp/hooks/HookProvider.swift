import CioInternalCommon
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingInAppModuleHookProvider: ModuleHookProvider {
    private var diGraph: DIGraph? {
        // FIXME: [CDP] Get the right DIGraph
        nil
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        // guard let diGraph = diGraph else { return nil }

        // FIXME: [CDP] Find workaround by attaching hook to Journeys or reusing existing instance to utilize customer provided siteid
        MessagingInApp.shared.implementation as? MessagingInAppImplementation
    }

    var screenTrackingHook: ScreenTrackingHook? {
        // guard let diGraph = diGraph else { return nil }

        // FIXME: [CDP] Find workaround by attaching hook to Journeys or reusing existing instance to utilize customer provided siteid
        MessagingInApp.shared.implementation as? MessagingInAppImplementation
    }
}
