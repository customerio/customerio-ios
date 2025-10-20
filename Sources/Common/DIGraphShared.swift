import Foundation

public class DIGraphShared: DIManager {
    public static let shared: DIGraphShared = .init()

    // MARK: - Storage

    /// Thread-safe storage for singletons dictionary using EnhancedSynchronized
    private let singletons = EnhancedSynchronized<[String: Any]>([:], label: "io.customer.DIGraphShared.singletons")
    
    /// Thread-safe storage for overrides dictionary using EnhancedSynchronized
    private let overrides = EnhancedSynchronized<[String: Any]>([:], label: "io.customer.DIGraphShared.overrides")

    // MARK: - Singleton Creation Synchronization
    
    /// Lock to protect access to the creationLocks dictionary itself
    private let creationLocksLock = NSLock()
    
    /// Per-type locks to ensure only one thread creates each singleton type
    /// Protected by creationLocksLock when accessing/modifying this dictionary
    private var creationLocks: [String: NSLock] = [:]
    
    /// Get or create a lock for a specific type key
    private func getCreationLock(for key: String) -> NSLock {
        creationLocksLock.lock()
        defer { creationLocksLock.unlock() }
        
        if let existingLock = creationLocks[key] {
            return existingLock
        }
        
        let newLock = NSLock()
        creationLocks[key] = newLock
        return newLock
    }

    // MARK: - Public Protocol Methods

    /// Designed to be used only in test classes to override dependencies.
    public func override<T: Any>(value: T, forType type: T.Type) {
        let key = String(describing: type)
        overrides.mutate { dict in
            dict[key] = value
        }
    }

    /// Retrieves an overridden instance of a specified type.
    public func getOverriddenInstance<T: Any>() -> T? {
        let key = String(describing: T.self)
        return overrides.get()[key] as? T
    }

    /// Reset the DI graph (useful for testing). Thread-safe atomic operation.
    public func reset() {
        singletons.mutate { dict in
            dict.removeAll()
        }
        overrides.mutate { dict in
            dict.removeAll()
        }
        creationLocksLock.lock()
        creationLocks.removeAll()
        creationLocksLock.unlock()
    }

    /// Thread-safe atomic singleton creation with double-checked locking.
    /// Uses NSLock for per-type creation synchronization and EnhancedSynchronized for storage.
    /// Factory is called OUTSIDE the storage lock to avoid deadlock when
    /// the factory needs to resolve other dependencies from this DI graph.
    public func getOrCreateSingleton<T>(forType type: T.Type, factory: () -> T) -> T {
        let key = String(describing: type)
        
        // Phase 1: Fast path - check if override exists (read from overrides storage)
        if let override = overrides.get()[key] as? T {
            return override
        }
        
        // Phase 2: Fast path - check if singleton already exists (read from singletons storage)
        if let existing = singletons.get()[key] as? T {
            return existing
        }
        
        // Phase 3: Acquire per-type creation lock to ensure only one thread creates this singleton
        let creationLock = getCreationLock(for: key)
        creationLock.lock()
        defer { creationLock.unlock() }
        
        // Phase 4: Double-check after acquiring creation lock
        if let override = overrides.get()[key] as? T {
            return override
        }
        if let existing = singletons.get()[key] as? T {
            return existing
        }
        
        // Phase 5: Create singleton (only one thread reaches here per type)
        // Factory is called with NO locks held on storage, avoiding deadlock
        let newInstance = factory()
        
        // Phase 6: Store the singleton (write to storage)
        singletons.mutate { dict in
            dict[key] = newInstance
        }
        
        return newInstance
    }
}
