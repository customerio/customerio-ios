import CioInternalCommon
import Foundation
import Segment

extension Configuration {
    // TODO: Module Level configuration is going to be added here which will replace this config
    static var defaultConfiguration: Configuration {
        configure(diGraph: CustomerIO.shared.diGraph)
    }

    static func configure(diGraph: DIGraph?) -> Configuration {
        let siteId = diGraph?.sdkConfig.siteId ?? ""
        let apiKey = diGraph?.sdkConfig.apiKey ?? ""
        let key = siteId + apiKey
        return Configuration(writeKey: key)
    }
}
