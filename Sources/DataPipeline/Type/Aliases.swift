import CioInternalCommon
import Foundation
import Segment

/*
 Contains public aliases to expose public structures/protocols from the 'Segment' module
 to the 'DataPipeline' module. The goal is that customers do not need to import
 the 'Segment' module in their code.
 */

public typealias Plugin = Segment.Plugin
public typealias PluginType = Segment.PluginType
public typealias EventPlugin = Segment.EventPlugin
public typealias DestinationPlugin = Segment.DestinationPlugin
public typealias UtilityPlugin = Segment.UtilityPlugin
public typealias VersionedPlugin = Segment.VersionedPlugin

public typealias Analytics = Segment.Analytics

public typealias RawEvent = Segment.RawEvent
public typealias TrackEvent = Segment.TrackEvent
public typealias ScreenEvent = Segment.ScreenEvent
public typealias AliasEvent = Segment.AliasEvent
public typealias GroupEvent = Segment.GroupEvent
public typealias IdentifyEvent = Segment.IdentifyEvent

public typealias Settings = Segment.Settings
public typealias FlushPolicy = Segment.FlushPolicy
public typealias OperatingMode = Segment.OperatingMode

public typealias Metric = CioInternalCommon.Metric
public typealias CustomerIO = CioInternalCommon.CustomerIO
public typealias CioLogLevel = CioInternalCommon.CioLogLevel
