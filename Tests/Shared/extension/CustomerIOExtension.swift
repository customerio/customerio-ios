@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import Segment

public extension CustomerIO {
    var analytics: Analytics? {
        (implementation as? DataPipelineImplementation)?.analytics
    }
}
