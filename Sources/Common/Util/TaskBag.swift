import Foundation

/*
 A convenient data type to easily keep track of Swift async Tasks and be able to cancel them all when the class is deinitialized.

 - Create instance: let taskBag: TaskBag = []
 - Add new Tasks: taskBag += Task { ... }
 - Cancel all tasks:
 ```
 deinit {
   taskBag.cancelAll()
 }
 ```
 */
public typealias TaskBag = [Task<Void, Error>]

extension TaskBag {
    static func += (left: inout [Task<Void, Error>], right: Task<Void, Error>) {
        left.append(right)
    }

    func cancelAll() {
        forEach { task in
            task.cancel()
        }
    }
}
