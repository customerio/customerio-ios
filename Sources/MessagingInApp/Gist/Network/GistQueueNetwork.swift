import CioInternalCommon
import Foundation

protocol GistQueueNetwork: AutoMockable {
    func request(
        state: InAppMessageState,
        request: GistNetworkRequest,
        completionHandler: @escaping (Result<GistNetworkResponse, Error>) -> Void
    ) throws
}

// sourcery: InjectRegisterShared = "GistQueueNetwork"
class GistQueueNetworkImpl: GistQueueNetwork {
    typealias GistNetworkResponse = (Data, HTTPURLResponse)

    func request(
        state: InAppMessageState,
        request: GistNetworkRequest,
        completionHandler: @escaping (Result<GistNetworkResponse, Error>) -> Void
    ) throws {
        guard let baseURL = URL(string: state.environment.networkSettings.queueAPI) else {
            throw GistNetworkRequestError.invalidBaseURL
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(request.path))
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.addValue(state.siteId, forHTTPHeaderField: HTTPHeader.siteId.rawValue)
        urlRequest.addValue(state.dataCenter, forHTTPHeaderField: HTTPHeader.cioDataCenter.rawValue)
        if let userToken = state.userId {
            urlRequest.addValue(Data(userToken.utf8).base64EncodedString(), forHTTPHeaderField: HTTPHeader.userToken.rawValue)
        }
        urlRequest.addValue(ContentTypes.json.rawValue, forHTTPHeaderField: HTTPHeader.contentType.rawValue)

        try BaseNetwork.request(
            request,
            urlRequest: urlRequest,
            baseURL: baseURL,
            completionHandler: completionHandler
        )
    }
}
