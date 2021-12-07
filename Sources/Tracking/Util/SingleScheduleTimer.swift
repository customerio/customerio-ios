import Foundation

/// Timer that only schedules once. Further calls result in ignored request until the timer fires.
internal protocol SingleScheduleTimer: AutoMockable {
    func scheduleIfNotAleady(numSeconds: Double, block: @escaping () -> Void) -> Bool
    func cancel()
}

// Since Queue isn't a singleton, we need timer to be so we don't start a new timer instance
// for each time that a queue item is added.
// sourcery: InjectRegister = "SingleScheduleTimer"
// sourcery: InjectSingleton
internal class CioSingleScheduleTimer: SingleScheduleTimer {
    @Atomic private var timer: Timer?
    @Atomic private var lock = Lock()

    deinit {
        unsafeCancel()
    }

    func scheduleIfNotAleady(numSeconds: Double, block: @escaping () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard timer == nil else {
            return false
        }

        timer = Timer.scheduledTimer(withTimeInterval: numSeconds, repeats: false, block: { timer in
            timer.invalidate()
            self.timer = nil

            block()
        })

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
