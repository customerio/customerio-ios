import Common
import Foundation

public protocol SdkInitializedUtil: AutoMockable {
    var isInitlaized: Bool { get }
    var postInitializedData: (siteId: String, diGraph: DIGraph)? { get }
}

public class SdkInitializedUtilImpl: SdkInitializedUtil {
    // Try to not use dependencies in this class as it's contructed before
    // DI graph could be populated. So, production code calls this constructor.
    public init() {}

    public var isInitlaized: Bool {
        CustomerIO.shared.diGraph != nil
    }

    public var postInitializedData: (siteId: String, diGraph: DIGraph)? {
        guard let siteId = CustomerIO.shared.siteId,
              let diGraph = CustomerIO.shared.diGraph
        else {
            return nil
        }

        return (siteId: siteId, diGraph: diGraph)
    }
}
