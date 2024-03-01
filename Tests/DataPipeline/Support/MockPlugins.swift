import CioDataPipelines
import Foundation
import Segment

class UtilityPluginMock: Plugin {
    let type: Segment.PluginType = .utility
    var analytics: Segment.Analytics?
}

class DestinationPluginMock: DestinationPlugin {
    let key: String = "Mock"
    let timeline: Segment.Timeline = .init()
    let type: Segment.PluginType = .destination
    var analytics: Segment.Analytics?
}
