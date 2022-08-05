@testable import Common
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public class HttpRequestRunnerStub {
    private var responseQueue: [HttpResponse] = []

    public var requestCallsCount: Int = 0

    public func queueNoRequestMade() {
        responseQueue.append(HttpResponse(data: nil, response: nil, error: URLError(.cancelled)))
    }

    public func queueSuccessfulResponse() {
        let code = 200
        let data = "".data!

        queueSuccessfulResponse(code: code, data: data)
    }

    public func queueSuccessfulResponse(code: Int, data: Data) {
        responseQueue.append(HttpResponse(
            data: data,
            response: HTTPURLResponse(
                url: "https://customer.io".url!,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            ),
            error: nil
        ))
    }
}

extension HttpRequestRunnerStub: HttpRequestRunner {
    public func request(
        _ params: HttpRequestParams,
        httpBaseUrls: HttpBaseUrls,
        session: URLSession,
        onComplete: @escaping (Data?, HTTPURLResponse?, Error?) -> Void
    ) {
        requestCallsCount += 1

        let queueNextResponse = responseQueue.removeFirst()

        onComplete(queueNextResponse.data, queueNextResponse.response, queueNextResponse.error)
    }

    public func downloadFile(
        url: URL,
        fileType: DownloadFileType,
        session: URLSession,
        onComplete: @escaping (URL?) -> Void
    ) {}

    private struct HttpResponse {
        let data: Data?
        let response: HTTPURLResponse?
        let error: Error?
    }
}
