import Foundation

public typealias SiteId = String

public extension SiteId {
    var abbreviatedSiteId: String {
        self[0 ..< 5]
    }
}
