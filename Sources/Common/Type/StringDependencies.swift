import Foundation

/**
 The code generator tool we use (Sourcery) to generate our dependency injection graph
 uses the data *type* for a dependency. That means that we need to differentiate
 one string (site-id) from another string (api key).

 To do that, we create a special data type for every dependency in our graph.
 */
public typealias SiteId = String

public extension SiteId {
    var abbreviatedSiteId: String {
        self[0 ..< 5]
    }
}

public typealias ApiKey = String
