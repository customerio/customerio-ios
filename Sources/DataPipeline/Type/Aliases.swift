import CioAnalytics
// Re-exported so consumers can retroactively conform `CustomerIO` (declared in CioInternalCommon)
// without an extra `import CioInternalCommon`. Required by Member Import Visibility (Xcode 16.3+).
@_exported import CioInternalCommon
import Foundation

/*
 Contains public aliases to expose public structures/protocols from the 'CioInternalCommon' module
 to the 'DataPipeline' module.
 */
public typealias Metric = CioInternalCommon.Metric
public typealias CustomerIO = CioInternalCommon.CustomerIO
public typealias CioLogLevel = CioInternalCommon.CioLogLevel
public typealias Region = CioInternalCommon.Region
public typealias ScreenView = CioInternalCommon.ScreenView
