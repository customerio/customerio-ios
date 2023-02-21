import Common
import Foundation

public class ThreadUtilStub: ThreadUtil {
    public func runMain(_ block: @escaping () -> Void) {
        block()
    }

    public func queueOnBackground(_ block: @escaping () -> Void) {
        block()
    }
}
