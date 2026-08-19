import UIKit

/// Owns process-notification observation used to reset activation-scoped delegate state.
final class ApplicationActivationObserver {
    private enum State {
        case idle
        case starting
        case observing(NSObjectProtocol)
    }

    private let lock = NSLock()
    private let addObserver: (@escaping () -> Void) -> NSObjectProtocol
    private let removeObserver: (NSObjectProtocol) -> Void
    private var state = State.idle

    init(
        addObserver: @escaping (@escaping () -> Void) -> NSObjectProtocol = { callback in
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { _ in callback() }
        },
        removeObserver: @escaping (NSObjectProtocol) -> Void = {
            NotificationCenter.default.removeObserver($0)
        }
    ) {
        self.addObserver = addObserver
        self.removeObserver = removeObserver
    }

    /// Starts observation without holding the notification-center installation lock.
    ///
    /// The `starting` state prevents a synchronously reentrant registration from recursively adding observers.
    /// Concurrent installers retain one token, while `addObserver` and `removeObserver` remain outside every
    /// SDK lock.
    func start(onWillEnterForeground: @escaping () -> Void) {
        lock.lock()
        guard case .idle = state else {
            lock.unlock()
            return
        }
        state = .starting
        lock.unlock()

        let candidate = addObserver(onWillEnterForeground)

        lock.lock()
        let redundantObserver: NSObjectProtocol?
        if case .starting = state {
            state = .observing(candidate)
            redundantObserver = nil
        } else {
            redundantObserver = candidate
        }
        lock.unlock()

        if let redundantObserver {
            removeObserver(redundantObserver)
        }
    }

    deinit {
        lock.lock()
        let observer: NSObjectProtocol?
        if case .observing(let token) = state {
            observer = token
        } else {
            observer = nil
        }
        state = .idle
        lock.unlock()
        if let observer {
            removeObserver(observer)
        }
    }
}
