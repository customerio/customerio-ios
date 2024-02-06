import SharedTests

class DIGraphTests: BaseDIGraphTest {
    func testDependencyGraphComplete() {
        runTest_expectDiGraphResolvesAllDependenciesWithoutError()
    }
}
