import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public typealias HttpHeaders = [String: String]

public protocol HttpClient: AutoMockable {
    func request(
        _ params: HttpRequestParams,
        onComplete: @escaping (Result<Data, HttpRequestError>) -> Void
    )
    func downloadFile(url: URL, fileType: DownloadFileType, onComplete: @escaping (URL?) -> Void)
    func cancel(finishTasks: Bool)
}
