import CioInternalCommon
import Foundation

public class ThreadUtilStub: ThreadUtil {
    @Atomic public var runMainCallsCount = 0
    @Atomic public var runBackgroundCallsCount = 0

    public var runCount: Int {
        runMainCallsCount + runBackgroundCallsCount
    }

    public func runMain(_ block: @escaping () -> Void) {
        runMainCallsCount += 1

        block()
    }

    public func runBackground(_ block: @escaping () -> Void) {
        runBackgroundCallsCount += 1

        block()
    }
}
