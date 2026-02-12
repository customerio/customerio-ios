//
//  DataPipelineConfigKey.swift
//  Customer.io
//
//  Created by Holly Schilling on 2/11/26.
//


enum DataPipelineConfigKey: String {
    case flushPolicies = "flushPolicies"
    case flushAt = "flushAt"
    case flushInterval = "flushInterval"
    
    case autoAddCustomerIODestination = "autoAddCustomerIODestination"
    case trackApplicationLifecycleEvents = "trackApplicationLifecycleEvents"
    
    case autoTrackUIKitScreenViews = "autoTrackUIKitScreenViews"
    
    case autoTrackDeviceAttributes = "autoTrackDeviceAttributes"
    
    case migrationSiteId = "migrationSiteId"
    
    case screenViewUse = "screenViewUse"
    
    case deepLinkCallback = "deepLinkCallback"
    
    case apiHost = "apiHost"
    case cdnHost = "cdnHost"
}
