import Foundation

// Wrapping Timer class to be easier to work with SwiftUI Views.
// Because SwiftUI Views are structs, it's difficult to create new instances
// of objects. This class instead allows you to simply call start() or stop()
// without having to manage the Timer instance in the struct.
class SwiftUITimer {
    private var timer: Timer?
    private var callback: (() -> Void)?

    func start(interval: TimeInterval, callback: @escaping () -> Void) {
        self.callback = callback
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            callback()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
