@testable import CioMessagingInApp
import XCTest

class StringPercentEncodeTests: XCTestCase {
    func test_givenValidCharacter_expectEncodedURL() {
        let input = "https://example.com/path#fragment"

        let encoded = input.percentEncode(character: "#")

        XCTAssertEqual(encoded, "https://example.com/path%23fragment")
    }

    func test_givenMultipleOccurrences_expectAllEncoded() {
        let input = "https://example.com/path#fragment#another"

        let encoded = input.percentEncode(character: "#")

        XCTAssertEqual(encoded, "https://example.com/path%23fragment%23another")
    }

    func test_givenMultipleCharacter_expectEncodedGivenOnly() {
        let input = "https://example.com/path#source=link&medium=email"

        let encoded = input.percentEncode(character: "#")

        XCTAssertEqual(encoded, "https://example.com/path%23source=link&medium=email")
    }

    func test_givenCharacterInAllowedSet_expectUnchangedString() {
        let input = "https://example.com/path/fragment"

        // '/' is allowed in `.urlPathAllowed`
        let encoded = input.percentEncode(character: "/")

        XCTAssertEqual(encoded, input)
    }

    func test_givenCustomAllowedCharacterSet_expectEncodedSpaces() {
        let input = "https://example.com/path with spaces"

        let encoded = input.percentEncode(character: " ", withAllowedCharacters: .alphanumerics)

        XCTAssertEqual(encoded, "https://example.com/path%20with%20spaces")
    }

    func test_givenNoTargetCharacter_expectUnchangedString() {
        let input = "https://example.com/path/fragment"

        let encoded = input.percentEncode(character: "#")

        XCTAssertEqual(encoded, input)
    }

    func test_givenEmptyTargetCharacter_expectUnchangedString() {
        let input = "https://example.com/path/fragment"

        let encoded = input.percentEncode(character: "")

        XCTAssertEqual(encoded, input)
    }

    func test_givenEmptyInput_expectEmptyString() {
        let input = ""

        let encoded = input.percentEncode(character: "#")

        XCTAssertEqual(encoded, input)
    }
}
