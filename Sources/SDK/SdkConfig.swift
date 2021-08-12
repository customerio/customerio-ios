import Foundation

internal struct SdkConfig: AutoLenses, Equatable {
    let siteId: String
    let apiKey: String
    let region: Region

    // Other config options that are not provided by initialization of SDK function also go in this object.
    let devMode: Bool

    init(siteId: String, apiKey: String, region: Region, devMode: Bool = false) {
        self.siteId = siteId
        self.apiKey = apiKey
        self.region = region
        self.devMode = devMode
    }
}
