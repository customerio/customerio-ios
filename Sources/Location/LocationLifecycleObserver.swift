import Foundation

/// Owns app-lifecycle notification observers for the Location module (OnAppStart become-active and background).
/// Removes all observers in deinit when the instance is deallocated.
/// Held by LocationServicesImplementation (singleton), so the "has triggered this launch" state is per process.
///
/// When mode is `.off`, no observers are registered. For `.onAppStart`: if `initialAlreadyActive` is true, triggers once immediately; otherwise registers for didBecomeActive. Background observer is registered for `.manual` and `.onAppStart` only.
final class LocationLifecycleObserver {
    private var hasTriggeredOnAppStartThisLaunch = false

    private let mode: LocationTrackingMode
    private let onBecomeActive: () -> Void
    private let onBackground: () -> Void
    private let lifecycleNotifying: AppLifecycleNotifying
    private var observerTokens: [AppLifecycleObserverToken] = []

    /// - Parameter initialAlreadyActive: When true and mode is `.onAppStart`, triggers once immediately (caller should pass the result of reading app state on the main thread). Otherwise the observer registers for didBecomeActive. When mode is `.off`, no observers are registered.
    init(
        mode: LocationTrackingMode,
        onBecomeActive: @escaping () -> Void,
        onBackground: @escaping () -> Void,
        lifecycleNotifying: AppLifecycleNotifying,
        initialAlreadyActive: Bool = false
    ) {
        self.mode = mode
        self.onBecomeActive = onBecomeActive
        self.onBackground = onBackground
        self.lifecycleNotifying = lifecycleNotifying

        guard mode != .off else { return }

        // Background: register so we can stop location updates when app enters background.
        let backgroundToken = lifecycleNotifying.addDidEnterBackgroundObserver { [weak self] in
            guard let self else { return }
            self.onBackground()
        }
        observerTokens.append(backgroundToken)

        // Foreground / onAppStart: if already active, trigger once now; otherwise register for didBecomeActive.
        if mode == .onAppStart {
            if initialAlreadyActive {
                self.hasTriggeredOnAppStartThisLaunch = true
                onBecomeActive()
            } else {
                let token = lifecycleNotifying.addDidBecomeActiveObserver { [weak self] in
                    guard let self else { return }
                    if self.hasTriggeredOnAppStartThisLaunch { return }
                    self.hasTriggeredOnAppStartThisLaunch = true
                    self.onBecomeActive()
                }
                observerTokens.append(token)
            }
        }
    }

    deinit {
        for token in observerTokens {
            lifecycleNotifying.removeObserver(token)
        }
    }
}
