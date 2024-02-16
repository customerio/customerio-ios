import Foundation

public protocol CustomerIOInstance: AutoMockable {
    var siteId: String? { get }
    /// Get the current configuration options set for the SDK.
    var config: SdkConfig? { get }
}

/**
 Welcome to the Customer.io iOS SDK!

 This class is where you begin to use the SDK.
 You must call `CustomerIO.initialize` to use the features of the SDK.
 */
public class CustomerIO: CustomerIOInstance {
    /// The current version of the Customer.io SDK.
    public static var version: String {
        SdkVersion.version
    }

    public var siteId: String? {
        diGraph?.sdkConfig.siteId
    }

    /**
     Singleton shared instance of `CustomerIO`. Convenient way to use the SDK.

     Note: Don't forget to call `CustomerIO.initialize()` before using this!
     */
    @Atomic public private(set) static var shared = CustomerIO()

    // Only assign a value to this *when the SDK is initialzied*.
    // It's assumed that if this instance is not-nil, the SDK has been initialized.
    // Tip: Use `SdkInitializedUtil` in modules to see if the SDK has been initialized and get data it needs.
    public var implementation: CustomerIOInstance?

    // The 1 place that DiGraph is strongly stored in memory for the SDK.
    // Exposed for `SdkInitializedUtil`. Not recommended to use this property directly.
    public var diGraph: DIGraph?

    // private constructor to force use of singleton API
    private init() {}

    #if DEBUG
    // Methods to set up the test environment.
    // Any implementation of the interface works for unit tests.

    @discardableResult
    static func setUpSharedInstanceForUnitTest(implementation: CustomerIOInstance, diGraph: DIGraph) -> CustomerIO {
        shared.implementation = implementation
        shared.diGraph = diGraph
        return shared
    }

    public static func resetSharedTestEnvironment() {
        shared = CustomerIO()
    }
    #endif

    public static func initializeSharedInstance(with implementation: CustomerIOInstance, diGraph: DIGraph) {
        shared.implementation = implementation
        shared.diGraph = diGraph
        shared.postInitialize(diGraph: diGraph)
    }

    func postInitialize(diGraph: DIGraph) {
        let logger = diGraph.logger
        let siteId = diGraph.sdkConfig.siteId

        // Register the device token during SDK initialization to address device registration issues
        // arising from lifecycle differences between wrapper SDKs and native SDK.
        let globalDataStore = diGraph.globalDataStore
        if let token = globalDataStore.pushDeviceToken {
            // registerDeviceToken(token)
        }

        logger
            .info(
                "Customer.io SDK \(SdkVersion.version) initialized and ready to use for site id: \(siteId)"
            )
    }

    public var config: SdkConfig? {
        implementation?.config
    }
}
