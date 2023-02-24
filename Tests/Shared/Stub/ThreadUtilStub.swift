import Common
import Foundation

// Stub to make unit tests run synchronously if that's appropriate for the test.
public class ThreadUtilStub: ThreadUtil {
    public var mockCalled = false

    public func queueOnMain(_ block: @escaping () -> Void) {
        mockCalled = true

        block()
    }

    public func queueOnBackground(_ block: @escaping () -> Void) {
        mockCalled = true

        block()
    }
}
