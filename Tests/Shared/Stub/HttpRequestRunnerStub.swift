@testable import CioInternalCommon
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public class HttpRequestRunnerStub {
    // Runner either uses queue, or always returns the same response.
    private var responseQueue: [HttpResponse] = []
    private var responseToAlwaysReturn: HttpResponse?

    public private(set) var requestCallsCount: Int = 0
    public private(set) var requestsParams: [HttpRequestParams] = []

    public func queueNoRequestMade() {
        responseQueue.append(HttpResponse(data: nil, response: nil, error: URLError(.cancelled)))
    }

    public func queueSuccessfulResponse() {
        let code = 200
        let data = "".data!

        queueResponse(code: code, data: data)
    }

    public func queueResponse(code: Int, data: Data) {
        responseQueue.append(getHttpResponse(code: code, data: data))
    }

    // Careful when using this. Should be used only when the HTTP request is not relevant in the test function.
    // It's preferred to use one of the `queueX()` functions to better test the logic of the code under test.
    public func alwaysReturnSuccessfulResponse() {
        responseToAlwaysReturn = getHttpResponse(code: 200, data: "".data)
    }

    private func getHttpResponse(code: Int, data: Data) -> HttpResponse {
        HttpResponse(
            data: data,
            response: HTTPURLResponse(
                url: "https://customer.io".url!,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            ),
            error: nil
        )
    }
}

extension HttpRequestRunnerStub: HttpRequestRunner {
    public func request(
        params: HttpRequestParams,
        session: URLSession
    ) async throws -> (Data, URLResponse) {
        requestCallsCount += 1
        requestsParams.append(params)

        let queueNextResponse = responseToAlwaysReturn ?? responseQueue.removeFirst()
        
        if let error = queueNextResponse.error {
            throw error
        }
        
        guard let data = queueNextResponse.data, let response = queueNextResponse.response else {
            throw URLError(.badServerResponse)
        }
        
        return (data, response)
    }

    public func downloadFile(
        url: URL,
        fileType: DownloadFileType,
        session: URLSession
    ) async -> URL? {
        return nil
    }

    private struct HttpResponse {
        let data: Data?
        let response: HTTPURLResponse?
        let error: Error?
    }
}
