import CioInternalCommon

/// Key and region the SDK was set up with, shared with other modules through `DataPipelineTracking`.
extension DataPipelineImplementation {
    var apiKey: String {
        moduleConfig.cdpApiKey
    }

    var region: Region {
        moduleConfig.region
    }
}
