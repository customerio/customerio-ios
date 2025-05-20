import CioInternalCommon
import Foundation

public class ThreadUtilStub: ThreadUtil {
    public var runMainCalled = false
    public var runBackgroundCalled = false
    
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
    
    public func reset() {
        runMainCalled = false
        runBackgroundCalled = false
    }
}
