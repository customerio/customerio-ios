import CioInternalCommon
import Foundation

/// Request to download and attach a rich push image. Only created by the handler when the push
/// has a valid image URL. In-flight downloads are cancelled when `NSEPushCoordinator` invalidates the shared `HttpClient`.
class RichPushRequest {
    private let completionHandler: (PushNotification) -> Void
    private var push: PushNotification
    private let imageURL: URL
    private let httpClient: HttpClient

    /// `cancel()` runs on the coordinator path; `completeOnce()` runs on URLSession’s callback queue — synchronize to avoid double `completionHandler`.
    private let completionLock = NSLock()
    private var isCompleted = false

    init(
        push: PushNotification,
        imageURL: URL,
        httpClient: HttpClient,
        completionHandler: @escaping (PushNotification) -> Void
    ) {
        self.completionHandler = completionHandler
        self.push = push
        self.imageURL = imageURL
        self.httpClient = httpClient
    }

    func start() {
        httpClient.downloadFile(url: imageURL, fileType: .richPushImage) { [weak self] localFilePath in
            guard let self = self else { return }

            if let localFilePath = localFilePath {
                self.push.cioRichPushImageFile = localFilePath
            }

            self.completeOnce()
        }
    }

    /// Call when the request must be aborted (e.g. NSE expiry). Completes with current push state.
    /// Does not call `httpClient.cancel` — the NSE coordinator cancels the shared `HttpClient` once for the whole notification.
    func cancel() {
        completeOnce()
    }

    /// Delivers `completionHandler` at most once (coordinator expiry vs download completion). Invokes handler outside the lock.
    private func completeOnce() {
        completionLock.lock()
        guard !isCompleted else {
            completionLock.unlock()
            return
        }
        isCompleted = true
        let pushToDeliver = push
        completionLock.unlock()
        completionHandler(pushToDeliver)
    }
}
