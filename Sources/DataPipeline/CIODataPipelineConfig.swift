import CioInternalCommon
import Foundation
import Segment

extension Configuration {
    // TODO: Module Level configuration is going to be added here which will replace this config
    static var defaultConfiguration: Configuration {
        let siteId = CustomerIO.shared.config?.siteId ?? ""
        let apiKey = CustomerIO.shared.config?.apiKey ?? ""
        let key = siteId + apiKey
        return Configuration(writeKey: key)
    }
}
