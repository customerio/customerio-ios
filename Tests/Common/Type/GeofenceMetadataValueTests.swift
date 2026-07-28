@testable import CioInternalCommon
import Foundation
import Testing

@Suite("GeofenceMetadataValue")
struct GeofenceMetadataValueTests {
    // Wrapping in a dictionary avoids relying on top-level JSON fragment decoding.
    private func decode(_ jsonValue: String) throws -> GeofenceMetadataValue {
        let json = "{\"v\":\(jsonValue)}"
        let map = try JSONDecoder().decode([String: GeofenceMetadataValue].self, from: Data(json.utf8))
        return try #require(map["v"])
    }

    private func roundTrip(_ value: GeofenceMetadataValue) throws -> GeofenceMetadataValue {
        let data = try JSONEncoder().encode(["v": value])
        let map = try JSONDecoder().decode([String: GeofenceMetadataValue].self, from: data)
        return try #require(map["v"])
    }

    // MARK: - Decoding by primitive type

    @Test
    func decode_givenString_expectStringCase() throws {
        #expect(try decode("\"office\"") == .string("office"))
    }

    @Test
    func decode_givenBool_expectBoolCaseNotNumber() throws {
        // Bool must win over Int so `true` isn't coerced to 1.
        #expect(try decode("true") == .bool(true))
        #expect(try decode("false") == .bool(false))
    }

    @Test
    func decode_givenInteger_expectIntCase() throws {
        #expect(try decode("42") == .int(42))
    }

    @Test
    func decode_givenLargeInteger_expectInt64Preserved() throws {
        #expect(try decode("9007199254740993") == .int(9007199254740993))
    }

    @Test
    func decode_givenDecimal_expectDoubleCase() throws {
        #expect(try decode("3.5") == .double(3.5))
    }

    @Test
    func decode_givenIntegerBeyondInt64_expectDoubleFallbackNoThrow() throws {
        // A number larger than Int64.max must not crash; it falls back to a Double (lossy but safe).
        guard case .double = try decode("99999999999999999999") else {
            Issue.record("expected .double fallback for an over-Int64 integer")
            return
        }
    }

    @Test
    func decode_givenNestedObject_expectThrows() {
        #expect(throws: (any Error).self) { try decode("{\"a\":1}") }
    }

    @Test
    func decode_givenArray_expectThrows() {
        #expect(throws: (any Error).self) { try decode("[1,2]") }
    }

    // MARK: - Round-trip preserves primitive type

    @Test
    func encodeDecode_givenEachType_expectTypePreserved() throws {
        for value: GeofenceMetadataValue in [.string("x"), .bool(true), .int(7), .double(1.25)] {
            #expect(try roundTrip(value) == value)
        }
    }

    // MARK: - anyValue

    @Test
    func anyValue_expectNativeTypes() {
        #expect(GeofenceMetadataValue.string("a").anyValue as? String == "a")
        #expect(GeofenceMetadataValue.bool(true).anyValue as? Bool == true)
        #expect(GeofenceMetadataValue.int(3).anyValue as? Int64 == 3)
        #expect(GeofenceMetadataValue.double(2.5).anyValue as? Double == 2.5)
    }
}
