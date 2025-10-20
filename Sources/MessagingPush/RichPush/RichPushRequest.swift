import CioInternalCommon
import Foundation

class RichPushRequest {
    private var push: PushNotification
    private let httpClient: HttpClient

    init(
        push: PushNotification,
        httpClient: HttpClient
    ) {
        self.push = push
        self.httpClient = httpClient
    }

    func start() async -> PushNotification {
        guard let image = push.cioImage?.url else {
            // no async operations or modifications to the notification to do. Therefore, let's just finish.
            return finishImmediately()
        }

        let localFilePath = await httpClient.downloadFile(url: image, fileType: .richPushImage)
        if let localFilePath = localFilePath {
            push.cioRichPushImageFile = localFilePath
        }
        return finishImmediately()

//        httpClient.downloadFile(url: image, fileType: .richPushImage) { [weak self] localFilePath in
//            guard let self = self else { return }
//
//            if let localFilePath = localFilePath {
//                self.push.cioRichPushImageFile = localFilePath
//            }
//
//            self.finishImmediately()
//        }
    }

    func finishImmediately() -> PushNotification {
        httpClient.cancel(finishTasks: false)
        return push
    }
}
