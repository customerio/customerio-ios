import Foundation

// allows us to more easily have automated tests with threading
public protocol ThreadUtil {
    /// Schedules deferrable bulk work that should not compete with user-visible operations.
    func runBackground(_ block: @escaping () -> Void)

    /// Schedules non-interactive work that should run above deferrable background processing.
    func runUtility(_ block: @escaping () -> Void)

    /// Schedules work that must execute on the main thread.
    func runMain(_ block: @escaping () -> Void)

    /// Schedules work that must execute in main-actor isolation.
    func runMainActor(_ block: @MainActor @escaping () -> Void)
}

public extension ThreadUtil {
    /// Preserves source compatibility for conformers that predate the utility scheduling seam.
    func runUtility(_ block: @escaping () -> Void) {
        runBackground(block)
    }

    /// Preserves source compatibility while honoring the existing `runMain` contract.
    func runMainActor(_ block: @MainActor @escaping () -> Void) {
        runMain {
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    block()
                }
            } else {
                // Be defensive for legacy/test conformers that execute `runMain` inline.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        block()
                    }
                }
            }
        }
    }
}

// sourcery: InjectRegisterShared = "ThreadUtil"
public class CioThreadUtil: ThreadUtil {
    public func runMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    public func runMainActor(_ block: @MainActor @escaping () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                block()
            }
        }
    }

    public func runBackground(_ block: @escaping () -> Void) {
        DispatchQueue.global(qos: .background).async(execute: block)
    }

    public func runUtility(_ block: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async(execute: block)
    }
}
