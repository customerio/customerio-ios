import Foundation

public extension OperationQueue {
    func addAsyncOperation(asyncBlock: @escaping () async -> Void) {
        addOperation(AsyncOperation(asyncBlock: asyncBlock))
    }
}

public final class AsyncOperation: Operation, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var activeTask: Task<Void, Never>?

    public let asyncBlock: () async -> Void

    public init(asyncBlock: @escaping () async -> Void) {
        self.asyncBlock = asyncBlock
    }

    // Only required when you want to manually start an operation
    // Ignored when an operation is added to a queue.
    override public var isAsynchronous: Bool { true }

    // State is accessed and modified in a thread safe and KVO   compliant way.
    private var _isExecuting: Bool = false
    override public private(set) var isExecuting: Bool {
        get {
            lock.withLock {
                _isExecuting
            }
        }
        set {
            willChangeValue(forKey: "isExecuting")
            lock.withLock {
                _isExecuting = newValue
            }
            didChangeValue(forKey: "isExecuting")
        }
    }

    private var _isFinished: Bool = false
    override public private(set) var isFinished: Bool {
        get {
            lock.withLock {
                _isFinished
            }
        }
        set {
            willChangeValue(forKey: "isFinished")
            lock.withLock {
                _isFinished = newValue
            }
            didChangeValue(forKey: "isFinished")
        }
    }

    override public func start() {
        guard !isCancelled else {
            finish()
            return
        }
        isFinished = false
        isExecuting = true
        main()
    }

    override public func main() {
        lock.withLock {
            activeTask = Task { [weak self] in
                guard let self, !isCancelled else { return }
                await asyncBlock()
                finish()
            }
        }
    }

    override public func cancel() {
        lock.withLock {
            activeTask?.cancel()
            activeTask = nil
        }
        super.cancel()
    }

    func finish() {
        isExecuting = false
        isFinished = true
    }
}
