import Foundation
import Testing

@testable import CioInternalCommon

struct ArrayExtensionTest {
    // MARK: removeFirstOrNil

    @Test
    func test_removeFirstOrNil_givenEmptyArray_expectNil() {
        var given: [Int] = []

        #expect(given.removeFirstOrNil() == nil)
        #expect(given == [])
    }

    @Test
    func test_removeFirstOrNil_expectRemoveFirstAfterCall() {
        var given: [Int] = [1, 2, 3]

        _ = given.removeFirstOrNil()

        #expect(given == [2, 3])
    }

    @Test
    func test_removeFirstOrNil_expectNilAfterNoMoreItems() {
        var given: [Int] = [1, 2]

        let actual1 = given.removeFirstOrNil()
        let actual2 = given.removeFirstOrNil()
        let actual3 = given.removeFirstOrNil()

        #expect(actual1 == 1)
        #expect(actual2 == 2)
        #expect(actual3 == nil)
    }

    // MARK: mapNonNil

    @Test
    func test_mapNonNil_givenArrayNoNilValues_expectGetArray() {
        let given: [String?] = ["cio", "rocks"]
        let expected: [String] = ["cio", "rocks"]

        #expect(given.mapNonNil() == expected)
    }

    @Test
    func test_mapNonNil_givenEmptyArray_expectGetEmptyArray() {
        let given: [String?] = []
        let expected: [String] = []

        #expect(given.mapNonNil() == expected)
    }

    @Test
    func test_mapNonNil_givenArrayContainingNilValues_expectGetNonNilValuesOnly() {
        let given: [String?] = [nil, "cio", nil]
        let expected = ["cio"]

        #expect(given.mapNonNil() == expected)
    }
}
