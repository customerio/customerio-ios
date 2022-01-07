import Foundation

/// Wrapper for `Timer` with a simple API and ability to mock it to make tests run faster then
/// having to wait for a Timer to end.
internal protocol SimpleTimer: AutoMockable {
    func schedule(milliseconds: Milliseconds, block: @escaping () -> Void)
    func scheduleIfNotAleady(milliseconds: Milliseconds, block: @escaping () -> Void) -> Bool
    func cancel()
}

// sourcery: InjectRegister = "SimpleTimer"
internal class CioSimpleTimer: SimpleTimer {
    @Atomic private var timer: Timer?
    @Atomic private var lock = Lock()

    deinit {
        unsafeCancel()
    }

    func schedule(milliseconds: Milliseconds, block: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        let numSeconds = milliseconds.toSeconds

        timer = Timer.scheduledTimer(withTimeInterval: numSeconds, repeats: false, block: { timer in
            timer.invalidate()
            self.timer = nil

            block()
        })
    }

    func scheduleIfNotAleady(milliseconds: Milliseconds, block: @escaping () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard timer == nil else {
            return false
        }

        schedule(milliseconds: milliseconds, block: block)

        return true
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }

        unsafeCancel()
    }

    private func unsafeCancel() {
        timer?.invalidate()
        timer = nil
    }
}
