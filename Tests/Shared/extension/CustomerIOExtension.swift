@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import Segment

public extension CustomerIO {
    var dataPipelineImplementation: DataPipelineImplementation? { implementation as? DataPipelineImplementation }
    var analytics: Analytics? { dataPipelineImplementation?.analytics }
}
