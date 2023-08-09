@testable import CioInternalCommon
import Foundation
import XCTest

/**
 Each module of the SDK adds more dependencies to the DiGraph. These dependencies are only available to that module which means that it's important that in each module, we test the DiGraph.

 That could mean lots of copy/paste. To avoid that, this base class exists to subclass in each module.

 In each (test) module corresponding to each SDK module, create a test class:
 ```
 import SharedTests

 class DIGraphTests: BaseDIGraphTest {
     func testDependencyGraphComplete() {
         runTest_expectDiGraphResolvesAllDependenciesWithoutError()
     }
 }
 ```
 */
open class BaseDIGraphTest: IntegrationTest {
    public func runTest_expectDiGraphResolvesAllDependenciesWithoutError() {
        // Test will try to get an instance of every dependency in the graph.
        // If an exception is thrown, then there is a bug in the graph.
        let numberOfDependenciesResolved = diGraph.testDependenciesAbleToResolve()

        // check to make sure test works as we expect it to. Since the test is automatically generated for us.
        if numberOfDependenciesResolved <= 0 {
            XCTFail(
                "there is probably a bug with the dependency injection graph test. 0 depdencies were resolved which is probably a bug."
            )
        }
    }
}
