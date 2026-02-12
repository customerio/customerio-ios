//
//  LocationService.swift
//  Customer.io
//
//  Created by Holly Schilling on 2/11/26.
//

@_spi(Module) import CioInternalCommon

public extension CustomerIO {
    var location: LocationService {
        guard let module = findModule(LocationService.self) else {
            fatalError("Location Module not configured prior to use")
        }
        return module
    }
}


public final class LocationService: CIOModule {
    
    private weak var root: CustomerIO?
    
    public init(digraph: DIGraphShared) throws {
        // TODO
    }
    
    public func configure(with: SdkConfig, root: CustomerIO) async throws {
        self.root = root
        // TODO
    }
}
