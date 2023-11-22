import CioInternalCommon
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingInAppModuleHookProvider: ModuleHookProvider {
    private var diGraph: DIGraph? {
        // TODO Fix DIGraph
        nil
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        guard let diGraph = diGraph else { return nil }

        // FIXME: [CDP] Find workaround or reuse existing instance to utilize customer provided siteid
        return MessagingInAppImplementation(diGraph: diGraph, moduleConfig: MessagingInAppConfigOptions.Factory.create())
    }

    var screenTrackingHook: ScreenTrackingHook? {
        guard let diGraph = diGraph else { return nil }

        // FIXME: [CDP] Find workaround or reuse existing instance to utilize customer provided siteid
        return MessagingInAppImplementation(diGraph: diGraph, moduleConfig: MessagingInAppConfigOptions.Factory.create())
    }
}
