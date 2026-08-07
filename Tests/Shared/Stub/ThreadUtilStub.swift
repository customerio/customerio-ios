import CioInternalCommon
import Foundation

/// Runs every scheduled block inline on the calling thread and records how each one was scheduled.
///
/// Only counters are exposed on purpose. An injectable "call me back" closure would let a test attach
/// an `XCTestExpectation` to a stub whose lifetime it does not own, and any late block — from a timer,
/// a store replay, or a retained subscription — could then fulfil that expectation after the test
/// finished and crash whichever test happened to be running. Counters let tests inspect calls without
/// retaining XCTest state in an escaping closure.
public class ThreadUtilStub: ThreadUtil {
    private let _runMainCallsCount: Synchronized<Int> = .init(0)
    private let _runBackgroundCallsCount: Synchronized<Int> = .init(0)
    private let _runUtilityCallsCount: Synchronized<Int> = .init(0)

    public var runMainCallsCount: Int { _runMainCallsCount.wrappedValue }
    public var runBackgroundCallsCount: Int { _runBackgroundCallsCount.wrappedValue }
    public var runUtilityCallsCount: Int { _runUtilityCallsCount.wrappedValue }

    public var runMainCalled: Bool { runMainCallsCount > 0 }
    public var runBackgroundCalled: Bool { runBackgroundCallsCount > 0 }
    public var runUtilityCalled: Bool { runUtilityCallsCount > 0 }

    public init() {
        // Public initializer
    }

    public func runMain(_ block: @escaping () -> Void) {
        _runMainCallsCount.mutating { $0 += 1 }
        block()
    }

    public func runBackground(_ block: @escaping () -> Void) {
        _runBackgroundCallsCount.mutating { $0 += 1 }
        block()
    }

    public func runUtility(_ block: @escaping () -> Void) {
        _runUtilityCallsCount.mutating { $0 += 1 }
        block()
    }
}
