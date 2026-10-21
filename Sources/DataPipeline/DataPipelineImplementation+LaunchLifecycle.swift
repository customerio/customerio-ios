import CioAnalytics

extension DataPipelineImplementation {
    /// Apps that initialize the SDK after launch (React Native, Flutter) would otherwise never track
    /// Application Installed, Application Updated or the first Application Opened.
    func replayMissedLaunchLifecycleEvents(enabled: Bool) {
        #if os(iOS)
        guard enabled else { return }
        MissedLaunchLifecycleReplay(analytics: analytics).start()
        #endif
    }
}
