import Foundation

/// Owns app-lifecycle notification observers for the Location module (OnAppStart become-active and background).
/// Tokens unregister themselves when deallocated, so no explicit teardown is needed.
/// Held by LocationServicesImplementation (singleton), so the "has triggered this launch" state is per process.
///
/// When mode is `.off`, no observers are registered. For `.onAppStart`: register for didBecomeActive first (in init), then call `triggerIfAlreadyActive(applicationStateProvider:)` to check state and trigger once if app is already active. Background observer is registered for `.manual` and `.onAppStart` only.
final class LocationLifecycleObserver {
    private var hasTriggeredOnAppStartThisLaunch = false

    private let mode: LocationTrackingMode
    private let onBecomeActive: () -> Void
    private let onBackground: () -> Void
    private let lifecycleNotifying: AppLifecycleNotifying
    private var observerTokens: [AppLifecycleObserverToken] = []

    /// - Parameter mode: When `.onAppStart`, didBecomeActive is registered in init (register first). Call `triggerIfAlreadyActive(applicationStateProvider:)` after init to check state and trigger once if already active.
    init(
        mode: LocationTrackingMode,
        onBecomeActive: @escaping () -> Void,
        onBackground: @escaping () -> Void,
        lifecycleNotifying: AppLifecycleNotifying
    ) {
        self.mode = mode
        self.onBecomeActive = onBecomeActive
        self.onBackground = onBackground
        self.lifecycleNotifying = lifecycleNotifying

        guard mode != .off else { return }

        // Foreground / onAppStart: register first so we never miss didBecomeActive; state check happens in triggerIfAlreadyActive().
        if mode == .onAppStart {
            let token = lifecycleNotifying.addDidBecomeActiveObserver { [weak self] in
                guard let self else { return }
                if self.hasTriggeredOnAppStartThisLaunch { return }
                self.hasTriggeredOnAppStartThisLaunch = true
                self.onBecomeActive()
            }
            observerTokens.append(token)
        }

        // Background: register so we can stop location updates when app enters background.
        let backgroundToken = lifecycleNotifying.addDidEnterBackgroundObserver { [weak self] in
            guard let self else { return }
            self.onBackground()
        }
        observerTokens.append(backgroundToken)
    }

    /// Checks app state on the main thread and triggers once if already active. Call after init when mode is `.onAppStart` so we don't miss the case where the app is already active at setup time.
    /// All reads/writes of `hasTriggeredOnAppStartThisLaunch` and the trigger run on main so they are serialized with the didBecomeActive notification block.
    func triggerIfAlreadyActive(applicationStateProvider: ApplicationStateProvider) async {
        guard mode == .onAppStart else { return }
        await MainActor.run { [weak self] in
            guard let self else { return }
            guard applicationStateProvider.applicationState == .active else { return }
            guard !self.hasTriggeredOnAppStartThisLaunch else { return }
            self.hasTriggeredOnAppStartThisLaunch = true
            self.onBecomeActive()
        }
    }
}
