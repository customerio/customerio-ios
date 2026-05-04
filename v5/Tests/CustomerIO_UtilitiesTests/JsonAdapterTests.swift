import Foundation
import Testing
@testable import CustomerIO_Utilities

// MARK: - Fixtures

private struct Person: Codable, Equatable {
    let name: String
    let age: Int
}

private struct Dated: Codable, Equatable {
    let timestamp: Date
}

// MARK: - Test Suite

@Suite struct JsonAdapterTests {

    private let adapter = JsonAdapter()

    // MARK: - Round-trip

    @Test func roundTripSimpleStruct() throws {
        let original = Person(name: "Alice", age: 30)
        let data = try adapter.encode(original)
        let decoded = try adapter.decode(Person.self, from: data)
        #expect(decoded == original)
    }

    @Test func roundTripArray() throws {
        let original = [Person(name: "A", age: 1), Person(name: "B", age: 2)]
        let data = try adapter.encode(original)
        let decoded = try adapter.decode([Person].self, from: data)
        #expect(decoded == original)
    }

    @Test func roundTripDictionary() throws {
        let original: [String: Int] = ["x": 1, "y": 2]
        let data = try adapter.encode(original)
        let decoded = try adapter.decode([String: Int].self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Date encoding is ISO 8601

    @Test func dateEncodedAsISO8601() throws {
        // Use a date whose ISO 8601 representation is easily verifiable
        let date = Date(timeIntervalSince1970: 0)
        let data = try adapter.encode(Dated(timestamp: date))
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("1970-01-01T00:00:00Z"))
    }

    @Test func dateRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Dated(timestamp: date)
        let data = try adapter.encode(original)
        let decoded = try adapter.decode(Dated.self, from: data)
        // ISO 8601 has 1-second precision, so compare within 1 second
        #expect(abs(decoded.timestamp.timeIntervalSince(date)) < 1)
    }

    // MARK: - Output formatting (sorted keys)

    @Test func outputHasSortedKeys() throws {
        struct ABC: Codable { let c: Int; let a: Int; let b: Int }
        let data = try adapter.encode(ABC(c: 3, a: 1, b: 2))
        let json = String(data: data, encoding: .utf8)!
        let aPos = json.range(of: "\"a\"")!.lowerBound
        let bPos = json.range(of: "\"b\"")!.lowerBound
        let cPos = json.range(of: "\"c\"")!.lowerBound
        #expect(aPos < bPos && bPos < cPos)
    }

    // MARK: - Decoding errors

    @Test func decodeInvalidDataThrows() {
        let garbage = Data([0xFF, 0xFE])
        #expect(throws: (any Error).self) {
            try adapter.decode(Person.self, from: garbage)
        }
    }

    @Test func decodeTypeMismatchThrows() throws {
        // Encode a string array, try to decode as Person
        let data = try adapter.encode(["hello"])
        #expect(throws: (any Error).self) {
            try adapter.decode(Person.self, from: data)
        }
    }

    // MARK: - DefaultInitializable conformance

    @Test func defaultInitializableProducesUsableInstance() throws {
        let adapter2 = JsonAdapter()
        let data = try adapter2.encode(Person(name: "Z", age: 99))
        let decoded = try adapter2.decode(Person.self, from: data)
        #expect(decoded.name == "Z")
    }
}
