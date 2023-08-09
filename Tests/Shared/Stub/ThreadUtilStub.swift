import CioInternalCommon
import Foundation

public class ThreadUtilStub: ThreadUtil {
    public func runMain(_ block: @escaping () -> Void) {
        block()
    }

    public func runBackground(_ block: @escaping () -> Void) {
        block()
    }
}
