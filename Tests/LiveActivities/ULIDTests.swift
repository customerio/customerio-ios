import Foundation
import Testing

@testable import CioLiveActivities

// MARK: - Format

struct ULIDFormatTests {
    /// Every character allowed in a canonical ULID (Crockford Base32, no I/L/O/U).
    private static let crockfordAlphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    @Test func generate_isExactly26Characters() {
        for _ in 0 ..< 1000 {
            #expect(ULID.generate().count == 26)
        }
    }

    @Test func generate_usesOnlyCrockfordAlphabet() {
        for _ in 0 ..< 1000 {
            let ulid = ULID.generate()
            #expect(ulid.allSatisfy { Self.crockfordAlphabet.contains($0) })
        }
    }

    @Test func generate_isAlreadyUppercase() {
        for _ in 0 ..< 1000 {
            let ulid = ULID.generate()
            #expect(ulid == ulid.uppercased())
        }
    }

    @Test func generate_leadingCharacter_isAtMost7() {
        // 26 * 5 = 130 bits but the value is only 128 bits, so the first character carries
        // just 3 significant timestamp bits and can never exceed '7'.
        for _ in 0 ..< 1000 {
            let leading = ULID.generate().first!
            #expect("01234567".contains(leading))
        }
    }

    @Test func generate_encodesCanonicalSpecVector() {
        // Canonical ULID spec example: 1469918176385 ms -> timestamp prefix "01ARYZ6S41"
        // (full spec ULID 01ARYZ6S41QJQECH4KPG6SEF3Y). Pins spec-exact encoding, not just a
        // decode round-trip.
        let date = Date(timeIntervalSince1970: 1469918176.385)
        #expect(ULID.generate(date: date).prefix(10) == "01ARYZ6S41")
    }
}

// MARK: - Uniqueness

struct ULIDUniquenessTests {
    @Test func generate_producesUniqueValues_overManyIterations() {
        var seen = Set<String>()
        for _ in 0 ..< 10000 {
            #expect(seen.insert(ULID.generate()).inserted)
        }
    }

    @Test func generate_randomnessDiffers_forSameTimestamp() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let a = ULID.generate(date: date)
        let b = ULID.generate(date: date)
        // Same timestamp prefix, but the 16-character randomness suffix should differ.
        #expect(a.prefix(10) == b.prefix(10))
        #expect(a.suffix(16) != b.suffix(16))
    }
}

// MARK: - Ordering

struct ULIDOrderingTests {
    @Test func generate_isLexicographicallyOrderedByTimestamp() {
        let earlier = ULID.generate(date: Date(timeIntervalSince1970: 1000))
        let middle = ULID.generate(date: Date(timeIntervalSince1970: 1700000000))
        let later = ULID.generate(date: Date(timeIntervalSince1970: 4000000000))
        #expect(earlier < middle)
        #expect(middle < later)
    }

    @Test func generate_millisecondResolution_ordersWithinSameSecond() {
        let base = Date(timeIntervalSince1970: 1700000000.000)
        let oneMillisLater = Date(timeIntervalSince1970: 1700000000.001)
        #expect(ULID.generate(date: base) < ULID.generate(date: oneMillisLater))
    }
}

// MARK: - Timestamp round-trip

struct ULIDTimestampTests {
    @Test func timestampDecode_roundTripsKnownValue() {
        // 1700000000 s -> 1_700_000_000_000 ms, which fits in 48 bits.
        let expectedMillis: UInt64 = 1700000000000
        let date = Date(timeIntervalSince1970: 1700000000)
        let ulid = ULID.generate(date: date)
        #expect(ULID.timestampMilliseconds(from: ulid) == expectedMillis)
    }

    @Test func timestampDecode_roundTripsEpochZero() {
        let ulid = ULID.generate(date: Date(timeIntervalSince1970: 0))
        #expect(ULID.timestampMilliseconds(from: ulid) == 0)
        // Timestamp portion of the epoch is all zeros.
        #expect(ulid.prefix(10) == "0000000000")
    }

    @Test func timestampDecode_returnsNil_forWrongLength() {
        #expect(ULID.timestampMilliseconds(from: "TOOSHORT") == nil)
    }

    @Test func timestampDecode_returnsNil_forNonCrockfordCharacter() {
        // 'I' is excluded from the Crockford alphabet.
        let invalid = "I" + String(repeating: "0", count: 25)
        #expect(ULID.timestampMilliseconds(from: invalid) == nil)
    }
}
