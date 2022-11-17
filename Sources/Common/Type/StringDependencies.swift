import Foundation

/**
 We store Strings in the dependency graph as dependencies. Example: being able to inject the site-id or api-key into a class... `init(siteId: String)`.

 The code generator tool we use (Sourcery) to generate our dependency injection graph
 uses the data *type* for a dependency and assumes that all dependency data types are unique. String is 1 data type and we have multiple Strings in the graph which breaks this rule.

 That means that we need to differentiate one string (site-id) from another string (api key). To do that, we create a unique data type for every String dependency in our graph. The easiest way to do that is using a typealias.
 */
public typealias SiteId = String

public extension SiteId {
    var abbreviatedSiteId: String {
        self[0 ..< 5]
    }
}

public typealias ApiKey = String
