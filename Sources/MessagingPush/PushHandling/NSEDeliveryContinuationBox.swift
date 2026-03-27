import Foundation

#if canImport(UserNotifications)

// MARK: - Delivery continuation (resume from metric callback or NSE cancel)

enum NSEDeliveryContinuationState: Sendable {
    case idle
    case waiting
    case resumed
    case cancelled
}

/// Bridges callback-based delivery tracking into async/await and allows `cancel()` to resume early.
final class NSEDeliveryContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state: NSEDeliveryContinuationState = .idle
    private var continuation: CheckedContinuation<Void, Never>?

    func install(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .idle:
            self.continuation = continuation
            state = .waiting

        case .cancelled, .resumed:
            continuation.resume()

        case .waiting:
            assertionFailure("NSEDeliveryContinuationBox.install called while already waiting")
            continuation.resume()
        }
    }

    @discardableResult
    func resumeIfNeeded(markCancelled: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .waiting:
            let continuation = self.continuation
            self.continuation = nil
            state = markCancelled ? .cancelled : .resumed
            continuation?.resume()
            return true

        case .idle:
            state = markCancelled ? .cancelled : .resumed
            return false

        case .resumed, .cancelled:
            return false
        }
    }
}

#endif
