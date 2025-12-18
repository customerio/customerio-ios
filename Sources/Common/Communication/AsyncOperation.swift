//
//  AsyncOperation.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/16/25.
//

import Foundation

extension OperationQueue {
    func addAsyncOperation(asyncBlock: @escaping () async -> Void) {
        addOperation(AsyncOperation(asyncBlock: asyncBlock))
    }
}

public final class AsyncOperation: Operation, @unchecked Sendable {
    
    private let activeTask: Synchronized<Task<Void, Never>?> = .init(initial: nil)
    
    public private(set) var asyncBlock: () async -> Void
    
    public init(asyncBlock: @escaping () async -> Void) {
        self.asyncBlock = asyncBlock
    }
    
    // Only required when you want to manually start an operation
    // Ignored when an operation is added to a queue.
    public override var isAsynchronous: Bool { return true }
    
    // State is accessed and modified in a thread safe and KVO   compliant way.
    private let _isExecuting: Synchronized<Bool> = .init(initial: false)
    public override private(set) var isExecuting: Bool {
        get {
            _isExecuting.value
        }
        set {
            willChangeValue(forKey: "isExecuting")
            _isExecuting.value = newValue
            didChangeValue(forKey: "isExecuting")
        }
    }
    
    private let _isFinished: Synchronized<Bool> = .init(initial: false)
    public private(set) override var isFinished: Bool {
        get {
            _isFinished.value
        }
        set {
            willChangeValue(forKey: "isFinished")
            _isFinished.value = newValue
            didChangeValue(forKey: "isFinished")
        }
    }
    
    public override func start() {
        guard !isCancelled else {
            finish()
            return
        }
        isFinished = false
        isExecuting = true
        main()
    }
    
    public override func main() {
        activeTask.value = Task {
            await asyncBlock()
            finish()
        }
    }
    
    public override func cancel() {
        activeTask.mutating { value in
            value?.cancel()
            value = nil
        }
        super.cancel()
    }
    
    func finish() {
        isExecuting = false
        isFinished = true
    }
}
