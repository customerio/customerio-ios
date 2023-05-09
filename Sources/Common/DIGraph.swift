import Foundation

public class DIGraph {
    public let sdkConfig: SdkConfig

    public init(sdkConfig: SdkConfig) {
        self.sdkConfig = sdkConfig
    }

    public var overrides: [String: Any] = [:]
    public var singletons: [String: Any] = [:]

    /**
     Designed to be used only in test classes to override dependencies.

     ```
     let mockOffRoadWheels = // make a mock of OffRoadWheels class
     DIGraph.shared.override(mockOffRoadWheels, OffRoadWheels.self)
     ```
     */
    public func override<Value: Any>(value: Value, forType type: Value.Type) {
        overrides[String(describing: type)] = value
    }

    /**
     Reset graph. Meant to be used in `tearDown()` of tests.
     */
    public func reset() {
        overrides = [:]
        singletons = [:]
    }
}
