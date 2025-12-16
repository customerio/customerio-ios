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

class AsyncOperation: Operation, @unchecked Sendable {
    
    // This is not the OperationQueue!
    // This is the queue we use to read and write the operation state  in a safe thread way
    private let queue = DispatchQueue(label: "async_operation_private_queue", attributes: .concurrent)
    
    private var activeTask: Task<Void, Never>?
    
    public private(set) var asyncBlock: () async -> Void
    
    public init(asyncBlock: @escaping () async -> Void) {
        self.asyncBlock = asyncBlock
    }
    
    // Only required when you want to manually start an operation
    // Ignored when an operation is added to a queue.
    override var isAsynchronous: Bool { return true }
    
    // State is accessed and modified in a thread safe and KVO   compliant way.
    private var _isExecuting: Bool = false
    override private(set) var isExecuting: Bool {
        get {
            return queue.sync { () -> Bool in return _isExecuting }
        }
        set {
            willChangeValue(forKey: "isExecuting")
            queue.sync(flags: [.barrier]) { _isExecuting = newValue }
            didChangeValue(forKey: "isExecuting")
        }
    }
    
    private var _isFinished: Bool = false
    override private(set) var isFinished: Bool {
        get {
            return queue.sync { () -> Bool in return _isFinished }
        }
        set {
            willChangeValue(forKey: "isFinished")
            queue.sync(flags: [.barrier]) { _isFinished = newValue }
            didChangeValue(forKey: "isFinished")
        }
    }
    
    override func start() {
        guard !isCancelled else {
            finish()
            return
        }
        isFinished = false
        isExecuting = true
        main()
    }
    
    override func main() {
        activeTask = Task {
            await asyncBlock()
            finish()
        }
    }
    
    override func cancel() {
        self.activeTask?.cancel()
        self.cancel()
    }
    
    func finish() {
        isExecuting = false
        isFinished = true
    }
}
