import CioInternalCommon
import Foundation

public class ThreadUtilStub: ThreadUtil {
    public var runMainCalled = false
    public var runBackgroundCalled = false
    public var runUtilityCalled = false
    public var runUtilityClosure: (() -> Void)?

    public init() {
        // Public initializer
    }

    public func runMain(_ block: @escaping () -> Void) {
        runMainCalled = true
        block()
    }

    public func runBackground(_ block: @escaping () -> Void) {
        runBackgroundCalled = true
        block()
    }

    public func runUtility(_ block: @escaping () -> Void) {
        runUtilityCalled = true
        runUtilityClosure?()
        block()
    }

    public func reset() {
        runMainCalled = false
        runBackgroundCalled = false
        runUtilityCalled = false
        runUtilityClosure = nil
    }
}
