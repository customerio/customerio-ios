@testable import CioInternalCommon
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

    // setLastCharacters

    func test_setLastCharacters_givenStringWithoutLastCharacters_expectAppendCharacters() {
        let given = "foo"
        let expected = "foo.jpg"

        XCTAssertEqual(given.setLastCharacters(".jpg"), expected)
    }

    func test_setLastCharacters_givenStringWithLastCharacters_expectUnmodifiedString() {
        let given = "foo.jpg"
        let expected = given

        XCTAssertEqual(given.setLastCharacters(".jpg"), expected)
    }

    // getFirstNCharacters

    func test_getFirstNCharacters_givenWantFirst5Characters_expectGetFirst5CharactersOfString() {
        let given = "1234567890"
        let expected = "12345"

        XCTAssertEqual(given.getFirstNCharacters(5), expected)
    }

    // isBlankOrEmpty
    func test_isBlankOrEmpty_givenEmptyString_expectTrue() {
        let given = "       "
        XCTAssertTrue(given.isBlankOrEmpty())
    }

    func test_isBlankOrEmpty_givenNonEmptyString_expectFalse() {
        let given = "Hello_World  123"
        XCTAssertFalse(given.isBlankOrEmpty())
    }
}
