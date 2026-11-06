import CioInternalCommon
import UIKit

/// Takes a Customer.io silent push and the completion handler for it. See ``MessagingPush/wrapperBackgroundPushHandler``.
@_spi(Internal)
public typealias WrapperBackgroundPushHandler = (CustomerIOBackgroundPush, @escaping (UIBackgroundFetchResult) -> Void) -> Bool

@_spi(Internal)
@available(iOSApplicationExtension, unavailable)
public extension MessagingPush {
    /// For Customer.io wrapper SDKs only, such as React Native and Flutter.
    ///
    /// `CioAppDelegateWrapper` calls it for each Customer.io silent push it receives, after saving the Delivered
    /// receipt, and never for other pushes. Return `true` to take the push: the app delegate isn't called, and the
    /// wrapper SDK calls the completion handler when its work ends. Only the first call counts, and the SDK completes
    /// with `.noData` if the wrapper SDK hasn't after 25 seconds. Return `false`, without calling the completion
    /// handler, to leave the push to the app delegate.
    static var wrapperBackgroundPushHandler: WrapperBackgroundPushHandler? {
        get { wrapperBackgroundPushHandlerStorage.wrappedValue }
        set { wrapperBackgroundPushHandlerStorage.wrappedValue = newValue }
    }
}

extension MessagingPush {
    /// What `CioAppDelegateWrapper` does with a remote notification before the app's handler runs: records a
    /// Customer.io silent push's Delivered receipt and offers the push to the wrapper SDK's handler. Calls `forward`
    /// with the completion handler to pass on, unless the wrapper SDK took the push.
    @available(iOSApplicationExtension, unavailable)
    static func receiveRemoteNotification(
        _ userInfo: [AnyHashable: Any],
        completionHandler: @escaping (UIBackgroundFetchResult) -> Void,
        forward: (@escaping (UIBackgroundFetchResult) -> Void) -> Void
    ) {
        guard case .received(let push) = recordBackgroundPush(userInfo: userInfo),
              let wrapperHandler = wrapperBackgroundPushHandler
        else {
            forward(completionHandler)
            return
        }
        let completion = BackgroundFetchCompletion(completionHandler)
        if wrapperHandler(push, completion.complete) {
            completion.scheduleCompletion(.noData, after: wrapperBackgroundPushTimeout.wrappedValue)
        } else {
            forward(completionHandler)
        }
    }

    static let wrapperBackgroundPushHandlerStorage = Synchronized<WrapperBackgroundPushHandler?>(nil)
    static let defaultWrapperBackgroundPushTimeout: TimeInterval = 25
    /// Seconds a wrapper SDK has to complete a push it took, under iOS's limit of about 30. Tests shorten it.
    static let wrapperBackgroundPushTimeout = Synchronized(defaultWrapperBackgroundPushTimeout)
}

/// Calls a background fetch completion handler once, however often it's asked to.
final class BackgroundFetchCompletion: @unchecked Sendable {
    private let completionHandler: (UIBackgroundFetchResult) -> Void
    private let completed = Synchronized(false)

    init(_ completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        self.completionHandler = completionHandler
    }

    func complete(_ result: UIBackgroundFetchResult) {
        guard !completed.atomicSetAndFetch(true) else { return }
        completionHandler(result)
    }

    /// Completes with `result` after `delay` seconds, unless completed before then.
    func scheduleCompletion(_ result: UIBackgroundFetchResult, after delay: TimeInterval) {
        Task { @MainActor [self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1000000000))
            complete(result)
        }
    }
}
