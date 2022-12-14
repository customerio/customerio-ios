import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol FileDownloadHttpClient: AutoMockable {
    func downloadFile(url: URL, fileType: DownloadFileType, onComplete: @escaping (URL?) -> Void)
    func cancel(finishTasks: Bool)
}

// sourcery: InjectRegister = "FileDownloadHttpClient"
public class FileDownloadHttpClientImpl: BaseHttpClient, FileDownloadHttpClient {
    private var httpRequestRunner: HttpRequestRunner
    private let logger: Logger

    init(
        httpRequestRunner: HttpRequestRunner,
        logger: Logger
    ) {
        self.httpRequestRunner = httpRequestRunner
        self.logger = logger

        super.init(session: Self.getBasicSession())
    }

    deinit {
        self.cancel(finishTasks: true)
    }

    public func downloadFile(url: URL, fileType: DownloadFileType, onComplete: @escaping (URL?) -> Void) {
        httpRequestRunner
            .downloadFile(url: url, fileType: fileType, session: session) { [weak self] localFileUrl, response, error in
                guard let self = self else { return }

                if let error = error {
                    if let error = self.isUrlError(error) {
                        self.logMessage("Network issue \(error)", url: url, wasSuccessful: false)

                        return onComplete(nil)
                    }

                    self.logMessage("Error not related to network \(error)", url: url, wasSuccessful: false)
                    return onComplete(nil)
                }

                guard let response = response else {
                    self.logMessage("No response back.", url: url, wasSuccessful: false)
                    return onComplete(nil)
                }

                let statusCode = response.statusCode
                guard statusCode < 300 else {
                    // error logLevel because getting a non-200 status code could indicate the file server operated by
                    // us or by the customer is having an issue and they should be informed about it.
                    self.logger
                        .error("Not able to download file. Got status code: \(statusCode) trying to download \(url)")
                    return onComplete(nil)
                }

                guard let localFileUrl = localFileUrl else {
                    self.logMessage("File not saved locally to device", url: url, wasSuccessful: false)
                    return onComplete(nil)
                }

                self.logMessage("", url: url, wasSuccessful: true)
                return onComplete(localFileUrl)
            }
    }

    private func logMessage(_ message: String, url: URL, wasSuccessful: Bool) {
        let message = wasSuccessful ? "File downloaded sucessfully. \(message). URL: \(url)" :
            "File download failure. \(message) URL: \(url)"

        logger.debug(message)
    }
}
