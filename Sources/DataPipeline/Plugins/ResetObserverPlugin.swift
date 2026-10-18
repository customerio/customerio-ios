import CioAnalytics

/// Calls `onReset` once `Analytics.reset()` has cleared the identity. Both `clearIdentify()` and `CustomerIO.reset()`
/// reach it.
class ResetObserverPlugin: UtilityPlugin {
    let type: PluginType = .utility
    weak var analytics: Analytics?

    private let onReset: () -> Void

    init(onReset: @escaping () -> Void) {
        self.onReset = onReset
    }

    func reset() {
        onReset()
    }
}
