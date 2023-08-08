import Foundation

internal protocol QueueInventoryMemoryStore {
    var inventory: [QueueTaskMetadata]? { get set }
}

// sourcery: InjectRegister = "QueueInventoryMemoryStore"
// sourcery: InjectSingleton
class QueueInventoryMemoryStoreImpl: QueueInventoryMemoryStore {
    @Atomic var inventory: [QueueTaskMetadata]?
}
