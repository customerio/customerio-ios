//
//  SDKConfigBuilder+Location.swift
//  Customer.io
//
//  Created by Holly Schilling on 2/11/26.
//

@_spi(Module) import CioInternalCommon

extension SDKConfigBuilder {
    
    public func setLocationTrackingMode(_ mode: TrackingMode) -> Self {
        self.enrollModule(LocationService.self)
        return self.setExtensionValue(mode, forKey: LocationConfigExtensionKey.trackingMode.rawValue)
    }
}
