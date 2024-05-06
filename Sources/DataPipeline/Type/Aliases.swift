import CioAnalytics
import CioInternalCommon
import Foundation

/*
 Contains public aliases to expose public structures/protocols from the 'Segment' module
 to the 'DataPipeline' module. The goal is that customers do not need to import
 the 'Segment' module in their code.
 */

public typealias Plugin = CioAnalytics.Plugin
public typealias PluginType = CioAnalytics.PluginType
public typealias EventPlugin = CioAnalytics.EventPlugin
public typealias DestinationPlugin = CioAnalytics.DestinationPlugin
public typealias UtilityPlugin = CioAnalytics.UtilityPlugin
public typealias VersionedPlugin = CioAnalytics.VersionedPlugin

public typealias Analytics = CioAnalytics.Analytics

public typealias RawEvent = CioAnalytics.RawEvent
public typealias TrackEvent = CioAnalytics.TrackEvent
public typealias ScreenEvent = CioAnalytics.ScreenEvent
public typealias AliasEvent = CioAnalytics.AliasEvent
public typealias GroupEvent = CioAnalytics.GroupEvent
public typealias IdentifyEvent = CioAnalytics.IdentifyEvent

public typealias Settings = CioAnalytics.Settings
public typealias FlushPolicy = CioAnalytics.FlushPolicy
public typealias OperatingMode = CioAnalytics.OperatingMode

public typealias Metric = CioInternalCommon.Metric
public typealias CustomerIO = CioInternalCommon.CustomerIO
public typealias CioLogLevel = CioInternalCommon.CioLogLevel
public typealias Region = CioInternalCommon.Region
