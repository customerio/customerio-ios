//
//  DependencyInjectionTests.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/9/25.
//

import Testing

@testable import CioInternalCommon

struct DependencyInjectionTests {
    
    @Test
    func testSimpleBuilder() async throws {
        
        let container: DependencyContainer = DependencyContainer.Builder()
            .register(singleton: "TestString")
            .register { _ in 42 }
            .build()
        
        let string: String = try await container.resolve()
        #expect(string == "TestString")
        
        let int: Int = try await container.resolve()
        #expect(int == 42)
    }
    
    @Test
    func testLazyConstruction() async throws {
        
        var constructorRun: Bool = false
        
        let container: DependencyContainer = DependencyContainer.Builder()
            .registerLazySingleton { _ in
                constructorRun = true
                return "LazyString"
            }
            .build()
        #expect(!constructorRun)
        let string: String = try await container.resolve()
        #expect(string == "LazyString")
        #expect(constructorRun)
    }
    
    @Test
    func testPostBuildRegistrationChange() async throws {

        let container: DependencyContainer = DependencyContainer.Builder()
            .register(singleton: "TestString")
            .register { _ in 42 }
            .build()
        
        await container.register(singleton: "UpdatedString")
        
        let string: String = try await container.resolve()
        #expect(string == "UpdatedString")
        
        let int: Int = try await container.resolve()
        #expect(int == 42)
    }
    
    @Test
    func testAutoAndDefaultConstructors() async throws {
        
        struct MyDefaultInitializable: DefaultInitializable { }
        struct MyAutoResolvable: Autoresolvable {
            init(resolver: any Resolver) throws { }
        }
        
        let container: DependencyContainer = DependencyContainer.Builder().build()
        
        _ = try await container.resolve(MyDefaultInitializable.self)
        _ = try await container.resolve(MyAutoResolvable.self)
    }

    
    @Test
    func testChainedResolutions() async throws {
        
        struct MyDefaultInitializable: DefaultInitializable { }
        struct MyAutoResolvable: Autoresolvable {
            var myString: String
            init(resolver: any Resolver) throws {
                myString = try resolver.resolve()
                let _: MyDefaultInitializable = try resolver.resolve()
                
            }
        }
        
        let container: DependencyContainer = DependencyContainer.Builder()
            .register(singleton: "TestString")
            .build()
        
        _ = try await container.resolve(MyAutoResolvable.self)
    }
    
    @Test
    func testResolvingThrowsIfCannotBeResolved() async throws {
        
        struct NonExistant { }
        
        let container: DependencyContainer = DependencyContainer.Builder().build()
        
        do {
            _ = try await container.resolve(NonExistant.self)
            Issue.record("Expected an error to be thrown")
        }
        catch { }
    }
    
    @Test
    func testSingletonResolution() async throws {
        
        struct InitCounter: DefaultInitializable {
            static var initCount: Int = 0
            init() {
                Self.initCount += 1
            }
        }

        let container: DependencyContainer = DependencyContainer.Builder().build()
        
        #expect(InitCounter.initCount == 0)
        let instance1: InitCounter = try await container.resolve()
        #expect(InitCounter.initCount == 1)
        let _: InitCounter = try await container.resolve()
        #expect(InitCounter.initCount == 2)
        
        await container.register(singleton: instance1)
        
        let _: InitCounter = try await container.resolve()
        #expect(InitCounter.initCount == 2)
        let _: InitCounter = try await container.resolve()
        #expect(InitCounter.initCount == 2)
    }
    
    @Test
    func testFailsAfterExpiration() async throws {
               
        struct MyAutoResolvable: Autoresolvable {
            static var savedResolver: Resolver? = nil
            var myString: String
            init(resolver: any Resolver) throws {
                Self.savedResolver = resolver
                myString = try resolver.resolve()
            }
        }
        
        let container: DependencyContainer = DependencyContainer.Builder()
            .register(singleton: "TestString")
            .register { _ in 42 }
            .build()

        #expect(MyAutoResolvable.savedResolver == nil)
        _ = try await container.resolve(MyAutoResolvable.self)
        #expect(MyAutoResolvable.savedResolver != nil)

        do {
            
            let _: String = try MyAutoResolvable.savedResolver!.resolve()
            
            Issue.record("Expected an error to be thrown")
        }
        catch let error as DependencyContainer.ResolutionError {
            if case DependencyContainer.ResolutionError.expired = error {
                // Expected error
            } else {
                Issue.record("Wrong error type thrown")
            }
        }
    }

}
