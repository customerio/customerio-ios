import Foundation

internal protocol HttpRetryPolicy: AutoMockable {
    var nextSleepTimeMilliseconds: Milliseconds? { get }
}

// sourcery: InjectRegister = "HttpRetryPolicy"
internal class CustomerIOAPIHttpRetryPolicy: HttpRetryPolicy {
    internal static let retryPolicyMilliseconds: [Milliseconds] = [
        100,
        200,
        400,
        800,
        1600,
        3200
    ]

    private var retriesLeft = CustomerIOAPIHttpRetryPolicy.retryPolicyMilliseconds

    var nextSleepTimeMilliseconds: Milliseconds? {
        retriesLeft.removeFirstOrNil()
    }
}
