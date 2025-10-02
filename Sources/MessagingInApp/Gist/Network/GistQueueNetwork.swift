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

        let sdkClient = DIGraphShared.shared.sdkClient

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(request.path))
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.addValue(state.siteId, forHTTPHeaderField: HTTPHeader.siteId.rawValue)
        urlRequest.addValue(state.dataCenter, forHTTPHeaderField: HTTPHeader.cioDataCenter.rawValue)
        urlRequest.addValue(sdkClient.sdkVersion, forHTTPHeaderField: HTTPHeader.cioClientVersion.rawValue)
        urlRequest.addValue(sdkClient.source.lowercased() + "-apple", forHTTPHeaderField: HTTPHeader.cioClientPlatform.rawValue)

        // Set user token: use userId if available, otherwise use anonymousId
        let isAnonymous: Bool
        if let userId = state.userId {
            urlRequest.addValue(Data(userId.utf8).base64EncodedString(), forHTTPHeaderField: HTTPHeader.userToken.rawValue)
            isAnonymous = false
        } else if let anonymousId = state.anonymousId {
            urlRequest.addValue(Data(anonymousId.utf8).base64EncodedString(), forHTTPHeaderField: HTTPHeader.userToken.rawValue)
            isAnonymous = true
        } else {
            isAnonymous = true
        }

        // Add anonymous header to indicate if user is anonymous
        urlRequest.addValue(String(isAnonymous), forHTTPHeaderField: HTTPHeader.userAnonymous.rawValue)
        urlRequest.addValue(ContentTypes.json.rawValue, forHTTPHeaderField: HTTPHeader.contentType.rawValue)

        try BaseNetwork.request(
            request,
            urlRequest: urlRequest,
            baseURL: baseURL,
            completionHandler: completionHandler
        )
    }
}
