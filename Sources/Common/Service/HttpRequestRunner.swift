import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 Exists to be able to mock http requests so we can test our HttpClient's response handling logic.
 */
public protocol HttpRequestRunner: AutoMockable {
    func request(
        params: HttpRequestParams,
        session: URLSession,
    ) async throws -> (Data, URLResponse)
    func downloadFile(url: URL, fileType: DownloadFileType, session: URLSession) async -> URL?
}

// sourcery: InjectRegisterShared = "HttpRequestRunner"
public class UrlRequestHttpRequestRunner: HttpRequestRunner {
    /**
     Note: When mocking request, open JSON file, convert to `Data`.
     */
    public func request(
        params: HttpRequestParams,
        session: URLSession
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: params.url)
        request.httpMethod = params.method
        request.httpBody = params.body
        params.headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        return try await session.data(for: request)
    }

    public func downloadFile(
        url: URL,
        fileType: DownloadFileType,
        session: URLSession
    ) async -> URL? {
        let directoryURL = fileType.directoryToSaveFiles(fileManager: FileManager.default)

        do {
            let (tempLocation, response) = try await session.download(from: url)

            guard let suggestedFileName = response.suggestedFilename else {
                return nil
            }

            // create a unique file name so when trying to move temp file to destination it doesn't give an exception
            let uniqueFileName = UUID().uuidString + "_" + suggestedFileName
            let destinationURL = directoryURL
                .appendingPathComponent(uniqueFileName)

            do {
                // confirm that directories all created because we may have created a new sub-directory
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                // Now attempt the move
                try FileManager.default.moveItem(at: tempLocation, to: destinationURL)
            } catch {
                // XXX: log error when error handling for the customer enabled

                return nil
            }

            return destinationURL
        } catch {
            return nil
        }

//        session.downloadTask(with: url) { tempLocation, response, _ in
//            guard let tempLocation = tempLocation, let suggestedFileName = response?.suggestedFilename else {
//                return onComplete(nil)
//            }
//
//            // create a unique file name so when trying to move temp file to destination it doesn't give an exception
//            let uniqueFileName = UUID().uuidString + "_" + suggestedFileName
//            let destinationURL = directoryURL
//                .appendingPathComponent(uniqueFileName)
//
//            do {
//                // confirm that directories all created because we may have created a new sub-directory
//                try FileManager.default.createDirectory(
//                    at: directoryURL,
//                    withIntermediateDirectories: true,
//                    attributes: nil
//                )
//
//                // Now attempt the move
//                try FileManager.default.moveItem(at: tempLocation, to: destinationURL)
//            } catch {
//                // XXX: log error when error handling for the customer enabled
//
//                return onComplete(nil)
//            }
//
//            onComplete(destinationURL)
//        }.resume()
    }
}
