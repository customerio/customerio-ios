import CioInternalCommon

// The `sdk.state` line: the identity, token and key the SDK holds, logged at each change so the latest line in a log
// is the current state. Logged after initialization, identify, a token stored or deleted, and a reset.
extension DataPipelineImplementation {
    /// Logs the state initialization restored, then again after each `Analytics.reset()`, which both
    /// `clearIdentify()` and `CustomerIO.reset()` reach.
    func startLoggingSdkState() {
        analytics.add(plugin: ResetObserverPlugin { [weak self] in self?.logSdkState() })
        logSdkState()
    }

    func logSdkState() {
        commonLogger.logSdkState(userId: registeredUserId, deviceToken: registeredDeviceToken, cdpApiKey: cdpApiKey)
    }
}
