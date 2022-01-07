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
    private var timer: SimpleTimer

    init(timer: SimpleTimer) {
        self.timer = timer
    }

    func scheduleIfNotAleady(numSeconds: Double, block: @escaping () -> Void) -> Bool {
        timer.scheduleIfNotAleady(milliseconds: numSeconds.toSeconds, block: block)
    }

    func cancel() {
        timer.cancel()
    }
}
