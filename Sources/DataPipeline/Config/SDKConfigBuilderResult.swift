import CioInternalCommon

/// Tuple type for the result of the `SDKConfigBuilder`'s `build` method.
/// Contains both `SdkConfig` and `DataPipelineConfigOptions` instances.
public typealias SDKConfigBuilderResult = (sdkConfig: SdkConfig, dataPipelineConfig: DataPipelineConfigOptions)
