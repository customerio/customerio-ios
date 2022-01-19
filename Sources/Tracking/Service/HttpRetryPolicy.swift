import Foundation

internal protocol HttpRetryPolicy: AutoMockable {
    var nextSleepTime: Seconds? { get }
}

// sourcery: InjectRegister = "HttpRetryPolicy"
internal class CustomerIOAPIHttpRetryPolicy: HttpRetryPolicy {
    internal static let retryPolicy: [Seconds] = [
        0.1,
        0.2,
        0.4,
        0.8,
        1.6,
        3.2
    ]

    private var retriesLeft = CustomerIOAPIHttpRetryPolicy.retryPolicy

    var nextSleepTime: Seconds? {
        retriesLeft.removeFirstOrNil()
    }
}
