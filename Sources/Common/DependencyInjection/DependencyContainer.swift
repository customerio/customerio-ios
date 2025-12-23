//
//  DependencyContainer.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/8/25.
//

public final class DependencyContainer: Sendable {
    
    public enum ResolutionError: Error {
        case notFound
        case typeMismatch(expected: Any.Type, actual: Any.Type)
        case expired
    }
    
    private class SimpleResolver: Resolver {
        
        public let container: DependencyContainer
        private let factories: [ObjectIdentifier: (SimpleResolver) throws -> Any]
        public private(set) var isExpired: Bool = false
        
        
        init(container: DependencyContainer, factories: [ObjectIdentifier: (SimpleResolver) throws -> Any]) {
            self.container = container
            self.factories = factories
        }
        
        public func resolve<T>() throws -> T {
            guard !isExpired else {
                throw ResolutionError.expired
            }
            
            let id = ObjectIdentifier(T.self)
            if let factory = factories[id] {
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

        public init() { }
        
        public func register<T>(_ type: T.Type = T.self, factory: @escaping (Resolver) throws -> T) -> Self {
            var result = self
            let id = ObjectIdentifier(type)
            result.factories[id] = factory
            
            return result
        }
        
        public func register<T>(as type: T.Type = T.self, singleton: T) -> Self {
            var result = self
            let id = ObjectIdentifier(T.self)
            result.factories[id] = { _ in singleton }
            
            return result
        }
        
        public func registerLazySingleton<T>(as type: T.Type = T.self, factory: @escaping (Resolver) throws -> T) -> Self {
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
                
        public func build() -> DependencyContainer {
            DependencyContainer(factories: factories)
        }

    }
    
    private let factories: Synchronized<[ObjectIdentifier: (Resolver) throws -> Any]>
    
    private init(factories: [ObjectIdentifier: (Resolver) throws -> Any]) {
        // Since our closures for lazy methods aren't sendable and concurrent reentry safe,
        // we disable concurrent reads.
        self.factories = Synchronized(initial: factories, allowConcurrentReads: false)
        
    }
        
    public func register<T>(_ type: T.Type = T.self, factory: @escaping (Resolver) throws -> T) {

        let id = ObjectIdentifier(type)
        factories[id] = factory
    }
    
    public func register<T>(_ type: T.Type = T.self, constructor: @escaping () -> T) {
        register { _ in constructor() }
    }
    
    public func register<T>(_ type: T.Type = T.self, singleton: @autoclosure @escaping () -> T) async {
        register { _ in singleton() }
    }
    
    public func registerLazySingleton<T>(_ type: T.Type = T.self, factory: @escaping (Resolver) throws -> T) async {
        
        var instance: T? = nil
        register { resolver in
            if let instance = instance {
                return instance
            }
            instance = try resolver.resolve()
            return instance!
        }
    }
    
    public func construct<T>(_ body: (Resolver) throws -> T) rethrows -> T {
        return try factories.using { factories in
            let resolver = SimpleResolver(container: self, factories: factories)
            let result = try body(resolver)
            resolver.expire()
            return result
        }
    }
    
    public func constructAsync<T>(_ body: @escaping (Resolver) throws -> T) async throws -> T {
        return try await factories.usingAsync { factories in
            let resolver = SimpleResolver(container: self, factories: factories)
            let result = try body(resolver)
            resolver.expire()
            return result
        }
    }
    
    public func resolve<T>() throws -> T {
        return try factories.using { factories in
            let resolver = SimpleResolver(container: self, factories: factories)
            let result: T = try resolver.resolve()
            resolver.expire()
            return result
        }
    }

    public func resolveAsync<T>() async throws -> T {
        return try await factories.usingAsync { factories in
            let resolver = SimpleResolver(container: self, factories: factories)
            let result: T = try resolver.resolve()
            resolver.expire()
            return result
        }
    }

}
