enum HTTPHeader: String {
    case contentType = "Content-Type"
    case siteId = "X-CIO-Site-Id"
    case cioDataCenter = "X-CIO-Datacenter"
    case userToken = "X-Gist-Encoded-User-Token"
    case cioClientVersion = "X-CIO-Client-Version"
    case cioClientPlatform = "X-CIO-Client-Platform"
}

enum ContentTypes: String {
    case json = "application/json"
}
