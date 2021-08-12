import Foundation

internal struct SdkConfig: Codable, AutoLenses {
    let siteId: String
    let apiKey: String
    let regionCode: String

    // Other config options that are not provided by initialization of SDK function also go in this object.
    // let devMode: Bool

    var region: Region {
        Region(rawValue: regionCode)!
    }
}
