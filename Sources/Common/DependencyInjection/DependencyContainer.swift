//
//  DependencyContainer.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/8/25.
//

public actor DependencyContainer {
    
    public enum ResolutionError: Error {
        case notFound
        case typeMismatch(expected: Any.Type, actual: Any.Type)
        case expired
    }
    
    private class SimpleResolver: Resolver {
        
        public let container: DependencyContainer
        public private(set) var isExpired: Bool = false
        
        
        init(container: DependencyContainer) {
            self.container = container
        }
        
        public func resolve<T>() throws -> T {
            guard !isExpired else {
                throw ResolutionError.expired
            }
            
            let id = ObjectIdentifier(T.self)
            if let factory = container.factories[id] {
                let untyped = try factory(self)
                guard let result = untyped as? T else {
                    throw ResolutionError.typeMismatch(expected: T.self, actual: type(of: untyped))
                }
                return result
            }
            
            if let autoresolvable = T.self as? Autoresolvable.Type {
                let instance = try autoresolvable.init(resolver: self)
                return instance as! T
            }
            
            if let defaultInit = T.self as? DefaultInitializable.Type {
                let instance = defaultInit.init()
                return instance as! T
            }
            
            throw ResolutionError.notFound
        }
        
        public func expire() {
            isExpired = true
        }
    }
    
    
    public struct Builder {
        private var factories: [ObjectIdentifier: (Resolver) throws -> Any] = [:]

        public func register<T>(_ type: T.Type = T.self, factory: @escaping (Resolver) throws -> T) -> Self {
            var result = self
            let id = ObjectIdentifier(type)
            result.factories[id] = factory
            
            return result
        }
        
        public func register<T>(_ type: T.Type = T.self, singleton: T) -> Self {
            var result = self
            let id = ObjectIdentifier(T.self)
            result.factories[id] = { _ in singleton }
            
            return result
        }
        
        public func registerLazySingleton<T>(_ type: T.Type = T.self, factory: @escaping (Resolver) throws -> T) -> Self {
            var result = self
            let id = ObjectIdentifier(T.self)
            
            var instance: T? = nil
            
            result.factories[id] = { resolver in
                if let instance = instance {
                    return instance
                }
                instance = try factory(resolver)
                return instance!
            }
            
            return result
        }
        
        func build() -> DependencyContainer {
            DependencyContainer(factories: factories)
        }

    }
    
    private nonisolated(unsafe) var factories: [ObjectIdentifier: (Resolver) throws -> Any] = [:]
    
    private init(factories: [ObjectIdentifier: (Resolver) throws -> Any]) {
        self.factories = factories
    }
    
    public func resolve<T>() async throws -> T {
        
        let resolver = SimpleResolver(container: self)
        let result: T = try resolver.resolve()
        resolver.expire()
        return result
    }
    
    public func register<T>(_ type: T.Type = T.self, factory: @escaping (Resolver) throws -> T) async {
        let id = ObjectIdentifier(type)
        self.factories[id] = factory
    }
    
    public func register<T>(_ type: T.Type = T.self, singleton: T) async {
        let id = ObjectIdentifier(T.self)
        self.factories[id] = { _ in singleton }
    }
    
    public func registerLazySingleton<T>(_ type: T.Type = T.self, factory: @escaping (Resolver) throws -> T) async {
        let id = ObjectIdentifier(T.self)
        
        var instance: T? = nil
        
        self.factories[id] = { resolver in
            if let instance = instance {
                return instance
            }
            instance = try resolver.resolve()
            return instance!
        }
    }
    
    public func construct<T>(factory: (Resolver) throws -> T) rethrows -> T {
        let resolver = SimpleResolver(container: self)
        let result = try factory(resolver)
        resolver.expire()
        return result
    }
    
    public func resolve<T>(_ type: T.Type = T.self) throws -> T {
        let resolver = SimpleResolver(container: self)
        let result: T = try resolver.resolve()
        resolver.expire()
        return result
    }
    
}
