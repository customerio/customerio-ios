import CioAnalytics
import CioDataPipelines
import Foundation

// This file contains mock plugins for testing purposes.
// These plugins can be used as placeholders for testing APIs that use plugins.

class UtilityPluginMock: Plugin {
    let type: PluginType = .utility
    var analytics: Analytics?
}

class DestinationPluginMock: DestinationPlugin {
    let key: String = "Mock"
    let timeline: Timeline = .init()
    let type: PluginType = .destination
    var analytics: Analytics?
}
