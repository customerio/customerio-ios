enum HTTPHeader: String {
    case contentType = "Content-Type"
    case siteId = "X-CIO-Site-Id"
    case cioDataCenter = "X-CIO-Datacenter"
    case userToken = "X-Gist-Encoded-User-Token"
    case userAnonymous = "X-Gist-User-Anonymous"
    case cioClientVersion = "X-CIO-Client-Version"
    case cioClientPlatform = "X-CIO-Client-Platform"
    case cioClientAppIdentifier = "X-CIO-Client-App-Identifier"
}

enum ContentTypes: String {
    case json = "application/json"
}
