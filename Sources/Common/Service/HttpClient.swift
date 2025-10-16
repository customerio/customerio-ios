import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public typealias HttpHeaders = [String: String]

public protocol HttpClient: AutoMockable {
//    func request(
//        _ params: HttpRequestParams,
//        onComplete: @escaping (Result<Data, HttpRequestError>) -> Void
//    )
    func request(_ params: CioInternalCommon.HttpRequestParams) async -> Result<Data, CioInternalCommon.HttpRequestError>
    func downloadFile(url: URL, fileType: DownloadFileType) async -> URL?
    func cancel(finishTasks: Bool)
}
