import CioMessagingPush
import Foundation

// File contains aliases to expose public classes from CioMessagingPush module.
// We want to avoid customers needing to ever import CioMessagingPush module and instead import the specific
// implementation that thier app uses (example: CioMessagingPushAPN).

public typealias MessagingPush = CioMessagingPush.MessagingPush
public typealias MessagingPushConfigBuilder = CioMessagingPush.MessagingPushConfigBuilder
public typealias MessagingPushConfigOptions = CioMessagingPush.MessagingPushConfigOptions
public typealias CustomerIOBackgroundPush = CioMessagingPush.CustomerIOBackgroundPush
public typealias CustomerIOBackgroundPushResult = CioMessagingPush.CustomerIOBackgroundPushResult
#if canImport(UserNotifications)
public typealias CustomerIOParsedPushPayload = CioMessagingPush.CustomerIOParsedPushPayload
#endif
