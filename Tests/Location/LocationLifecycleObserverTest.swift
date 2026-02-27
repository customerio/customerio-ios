@testable import CioLocation
import SharedTests
import Testing

@Suite("Location")
struct LocationLifecycleObserverTests {
    @Test
    func onAppStart_givenInactiveAndDidBecomeActiveOnce_expectOnBecomeActiveCalledOnce() {
        var becomeActiveCount = 0
        let stubLifecycle = StubAppLifecycleNotifying()
        let observer = LocationLifecycleObserver(
            mode: .onAppStart,
            onBecomeActive: { becomeActiveCount += 1 },
            onBackground: {},
            lifecycleNotifying: stubLifecycle,
            initialAlreadyActive: false
        )
        stubLifecycle.simulateDidBecomeActive()

        #expect(becomeActiveCount == 1)
    }

    @Test
    func onAppStart_givenInactiveAndDidBecomeActiveTwice_expectOnBecomeActiveCalledOnlyOnce() {
        var becomeActiveCount = 0
        let stubLifecycle = StubAppLifecycleNotifying()
        let observer = LocationLifecycleObserver(
            mode: .onAppStart,
            onBecomeActive: { becomeActiveCount += 1 },
            onBackground: {},
            lifecycleNotifying: stubLifecycle,
            initialAlreadyActive: false
        )
        _ = observer
        stubLifecycle.simulateDidBecomeActive()
        stubLifecycle.simulateDidBecomeActive()

        #expect(becomeActiveCount == 1)
    }

    @Test
    func onAppStart_givenModeManual_expectDidBecomeActiveDoesNotCallOnBecomeActive() {
        var becomeActiveCount = 0
        let stub = StubAppLifecycleNotifying()
        _ = LocationLifecycleObserver(
            mode: .manual,
            onBecomeActive: { becomeActiveCount += 1 },
            onBackground: {},
            lifecycleNotifying: stub
        )
        stub.simulateDidBecomeActive()

        #expect(becomeActiveCount == 0)
    }

    @Test
    func didEnterBackground_expectOnBackgroundCalled() {
        var backgroundCount = 0
        let stub = StubAppLifecycleNotifying()
        let observer = LocationLifecycleObserver(
            mode: .manual,
            onBecomeActive: {},
            onBackground: { backgroundCount += 1 },
            lifecycleNotifying: stub
        )
        _ = observer
        stub.simulateDidEnterBackground()

        #expect(backgroundCount == 1)
    }

    @Test
    func onAppStart_givenInitialAlreadyActive_expectOnBecomeActiveCalledImmediatelyAndNotAgainOnSimulate() {
        var becomeActiveCount = 0
        let stubLifecycle = StubAppLifecycleNotifying()
        let observer = LocationLifecycleObserver(
            mode: .onAppStart,
            onBecomeActive: { becomeActiveCount += 1 },
            onBackground: {},
            lifecycleNotifying: stubLifecycle,
            initialAlreadyActive: true
        )
        _ = observer
        #expect(becomeActiveCount == 1)
        stubLifecycle.simulateDidBecomeActive()
        #expect(becomeActiveCount == 1)
    }
}
