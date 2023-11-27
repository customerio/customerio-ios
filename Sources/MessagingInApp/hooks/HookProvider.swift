import CioInternalCommon
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingInAppModuleHookProvider: ModuleHookProvider {
    private var diGraph: DIGraph? {
        // FIXME: [CDP] Get the right DIGraph
        nil
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        guard let diGraph = diGraph else { return nil }

        return MessagingInAppImplementation(diGraph: diGraph)
    }

    var screenTrackingHook: ScreenTrackingHook? {
        guard let diGraph = diGraph else { return nil }

        return MessagingInAppImplementation(diGraph: diGraph)
    }
}
