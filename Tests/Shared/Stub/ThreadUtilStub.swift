import Common
import Foundation

/**
 XCtest tests can only run on a simulator instead of a physical device. Simulators behave differently then a physical device
 with the behavior of running code on different threads. This means that it's not possible to create test functions that test if code
 executes on a main or a backgroud thread.

 Instead, it's suggested that you stub code in tests for running code in separate threads (using this class), QA test the SDK to verify it behaves successfully with threads, and trust the OS will work as intended when running code on separate threads.
 */
public class ThreadUtilStub: ThreadUtil {
    public func queueOnMain(_ block: @escaping () -> Void) {
        block()
    }

    public func queueOnBackground(_ block: @escaping () -> Void) {
        block()
    }
}
