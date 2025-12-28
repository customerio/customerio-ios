import Foundation

// In-memory store of the BQ inventory. This acts as a cache to unnecessary reading the file system from the file system.
protocol QueueInventoryMemoryStore {
    var inventory: [QueueTaskMetadata]? { get set }
}

// The in-memory store should be a singleton to be re-used during the lifecycle of the SDK.
// Try to keep this class small because it's a singleton.
//
// sourcery: InjectSingleton
// sourcery: InjectRegisterShared = "QueueInventoryMemoryStore"
class QueueInventoryMemoryStoreImpl: QueueInventoryMemoryStore {
    
    private let _inventory = Synchronized<[QueueTaskMetadata]?>(initial: nil)
    var inventory: [QueueTaskMetadata]? {
        get { _inventory.wrappedValue }
        set { _inventory.wrappedValue = newValue }
    }
}
