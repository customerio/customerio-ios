@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class StringExtensionsTest: UnitTest {
    func test_data_expectConvertToAndFromData() {
        let givenString = String.random

        let data = givenString.data!

        let actual = data.string!

        XCTAssertEqual(givenString, actual)
    }

    func test_random_expectRandomStringCorrectLength() {
        let expected = 21

        let actual = String.random(length: expected)

        XCTAssertEqual(actual.count, expected)
    }

    func test_random_expectNotEmptyString() {
        XCTAssertTrue(!String.random.isEmpty)
    }

    func test_random_expectGetOnlyAlphabeticalCharacters() {
        let actual = String.random

        let filteredResult = actual.filter { character in
            String.abcLetters.contains(character)
        }

        XCTAssertEqual(filteredResult.count, actual.count)
    }

    // MARK: matches

    let regexPattern = #"[A-Z]*"# // only allows uppercase A-Z characters. https://regexr.com/63l2h

    func test_matches_givenStringNotMatchingAnyOfRegex_expectFalse() {
        let givenString = "0123"

        let actual = givenString.matches(regex: regexPattern)

        XCTAssertFalse(actual)
    }

    func test_matches_givenStringPartilyMatchesRegex_expectFalse() {
        let givenString = "0123A"

        let actual = givenString.matches(regex: regexPattern)

        XCTAssertFalse(actual)
    }

    func test_matches_givenStringMatchesRegex_expectTrue() {
        let givenString = "ABC"

        let actual = givenString.matches(regex: regexPattern)

        XCTAssertTrue(actual)
    }
}
