import CioInternalCommon
import Foundation
import Segment

public class CIODataPipeline {
    // Private static instance of Analytics, created only once.
    public private(set) static var analytics: Analytics = .init(configuration: Configuration.defaultConfiguration)

    // Private initializer to enforce singleton usage, prevents external instantiation.
    private init() {}

    // Method to reinitialize Analytics with a new configuration.
    public static func initialize(configuration: Configuration) {
        analytics = Analytics(configuration: configuration)
    }
}
