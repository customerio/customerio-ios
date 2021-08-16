import Foundation

internal struct SdkConfig: AutoLenses, Equatable {
    let siteId: String
    let apiKey: String
    let region: Region
}
