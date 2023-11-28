import CioInternalCommon
import Foundation
import Segment

public class CIODataPipeline {
    // Private static instance of Analytics, created only once.
    private static var analytics: Analytics = .init(configuration: Configuration.defaultConfiguration)

    // Private initializer to enforce singleton usage, prevents external instantiation.
    private init() {}

    // Static method to access the singleton Analytics instance.
    public static func shared() -> Analytics {
        analytics
    }

    // Method to reinitialize Analytics with a new configuration.
    public static func initialize(configuration: Configuration) {
        analytics = Analytics(configuration: configuration)
    }

    public static func initialize(diGraph: DIGraph) {
        analytics = Analytics(configuration: Configuration.configure(diGraph: diGraph))
    }
}
