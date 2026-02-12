//
//  SdkConfig+Location.swift
//  Customer.io
//
//  Created by Holly Schilling on 2/11/26.
//

@_spi(Module) import CioInternalCommon

public enum TrackingMode {
    case none
    case startupOnly
    case manualTriggering
    case automatic
}


extension SdkConfig {
    public var trackingMoode: TrackingMode {
        extensionValue(for: LocationConfigExtensionKey.trackingMode.rawValue, default: .none)
    }
}
