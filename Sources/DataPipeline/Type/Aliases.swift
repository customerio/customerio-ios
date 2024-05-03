import CDPAnalyticsSwift
import CioInternalCommon
import Foundation

/*
 Contains public aliases to expose public structures/protocols from the 'Segment' module
 to the 'DataPipeline' module. The goal is that customers do not need to import
 the 'Segment' module in their code.
 */

public typealias Plugin = CDPAnalyticsSwift.Plugin
public typealias PluginType = CDPAnalyticsSwift.PluginType
public typealias EventPlugin = CDPAnalyticsSwift.EventPlugin
public typealias DestinationPlugin = CDPAnalyticsSwift.DestinationPlugin
public typealias UtilityPlugin = CDPAnalyticsSwift.UtilityPlugin
public typealias VersionedPlugin = CDPAnalyticsSwift.VersionedPlugin

public typealias Analytics = CDPAnalyticsSwift.Analytics

public typealias RawEvent = CDPAnalyticsSwift.RawEvent
public typealias TrackEvent = CDPAnalyticsSwift.TrackEvent
public typealias ScreenEvent = CDPAnalyticsSwift.ScreenEvent
public typealias AliasEvent = CDPAnalyticsSwift.AliasEvent
public typealias GroupEvent = CDPAnalyticsSwift.GroupEvent
public typealias IdentifyEvent = CDPAnalyticsSwift.IdentifyEvent

public typealias Settings = CDPAnalyticsSwift.Settings
public typealias FlushPolicy = CDPAnalyticsSwift.FlushPolicy
public typealias OperatingMode = CDPAnalyticsSwift.OperatingMode

public typealias Metric = CioInternalCommon.Metric
public typealias CustomerIO = CioInternalCommon.CustomerIO
public typealias CioLogLevel = CioInternalCommon.CioLogLevel
public typealias Region = CioInternalCommon.Region
