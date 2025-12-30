import Foundation

extension OperationQueue {
    func addAsyncOperation(asyncBlock: @escaping () async -> Void) {
        addOperation(AsyncOperation(asyncBlock: asyncBlock))
    }
}

public final class AsyncOperation: Operation, @unchecked Sendable {
    private let syncQueue = DispatchQueue(label: "io.Customer.sdk.AsyncBlockOperation.syncQueue")
    private var activeTask: Task<Void, Never>?

    public private(set) var asyncBlock: () async -> Void

    public init(asyncBlock: @escaping () async -> Void) {
        self.asyncBlock = asyncBlock
    }

    // Only required when you want to manually start an operation
    // Ignored when an operation is added to a queue.
    override public var isAsynchronous: Bool { true }

    // State is accessed and modified in a thread safe and KVO   compliant way.
    private let _isExecuting: Synchronized<Bool> = .init(initial: false)
    override public private(set) var isExecuting: Bool {
        get {
            _isExecuting.wrappedValue
        }
        set {
            willChangeValue(forKey: "isExecuting")
            _isExecuting.wrappedValue = newValue
            didChangeValue(forKey: "isExecuting")
        }
    }

    private let _isFinished: Synchronized<Bool> = .init(initial: false)
    override public private(set) var isFinished: Bool {
        get {
            _isFinished.wrappedValue
        }
        set {
            willChangeValue(forKey: "isFinished")
            _isFinished.wrappedValue = newValue
            didChangeValue(forKey: "isFinished")
        }
    }

    override public func start() {
        syncQueue.sync {
            guard !isCancelled else {
                finish()
                return
            }
            isFinished = false
            isExecuting = true
            mainInternal()
        }
    }

    private func mainInternal() {
        activeTask = Task {
            await asyncBlock()
            finish()
        }
    }

    override public func main() {
        syncQueue.sync {
            mainInternal()
        }
    }

    override public func cancel() {
        syncQueue.sync {
            activeTask?.cancel()
            activeTask = nil
            super.cancel()
        }
    }

    private func finish() {
        isExecuting = false
        isFinished = true
    }
}
