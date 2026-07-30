import CioLiveActivities_Attributes
import Foundation
import Testing

// Codable + value semantics of `EpochSecondsDate` — the epoch-seconds wire format the Customer.io
// backend sends and ActivityKit decodes. Kept independent of the reporter so it documents the type
// on its own.
struct EpochSecondsDateTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Encoding

    @Test func encodesToIntegerSeconds() throws {
        // 2021-01-01T00:00:00Z == 1_609_459_200 s
        let sut = EpochSecondsDate(Date(timeIntervalSince1970: 1609459200))
        #expect(try String(decoding: encoder.encode(sut), as: UTF8.self) == "1609459200")
    }

    @Test func encodesEpochZero() throws {
        #expect(try String(decoding: encoder.encode(EpochSecondsDate(Date(timeIntervalSince1970: 0))), as: UTF8.self) == "0")
    }

    @Test func encodesNegativePre1970() throws {
        #expect(try String(decoding: encoder.encode(EpochSecondsDate(Date(timeIntervalSince1970: -1))), as: UTF8.self) == "-1")
    }

    @Test func encodeRoundsFractionalSecondsToNearest() throws {
        // The encoder rounds to the nearest whole second: .6 up, .4 down.
        #expect(try String(decoding: encoder.encode(EpochSecondsDate(Date(timeIntervalSince1970: 1609459200.6))), as: UTF8.self) == "1609459201")
        #expect(try String(decoding: encoder.encode(EpochSecondsDate(Date(timeIntervalSince1970: 1609459200.4))), as: UTF8.self) == "1609459200")
    }

    // MARK: - Decoding

    @Test func decodesFromIntegerSeconds() throws {
        let sut = try decoder.decode(EpochSecondsDate.self, from: Data("1609459200".utf8))
        #expect(sut.date == Date(timeIntervalSince1970: 1609459200))
    }

    @Test func decodesEpochZeroAndNegative() throws {
        #expect(try decoder.decode(EpochSecondsDate.self, from: Data("0".utf8)).date == Date(timeIntervalSince1970: 0))
        #expect(try decoder.decode(EpochSecondsDate.self, from: Data("-1".utf8)).date == Date(timeIntervalSince1970: -1))
    }

    @Test func decodeRejectsNonNumeric() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(EpochSecondsDate.self, from: Data("\"not-a-number\"".utf8))
        }
    }

    // MARK: - Round trip

    @Test func roundTrip_wholeSeconds_isExact() throws {
        let sut = EpochSecondsDate(Date(timeIntervalSince1970: 1700000000))
        let decoded = try decoder.decode(EpochSecondsDate.self, from: encoder.encode(sut))
        #expect(decoded == sut)
    }

    @Test func roundTrip_dropsSubSecondPrecision() throws {
        let sut = EpochSecondsDate(Date(timeIntervalSince1970: 1700000000.4))
        let decoded = try decoder.decode(EpochSecondsDate.self, from: encoder.encode(sut))
        #expect(decoded.date.timeIntervalSince1970 == 1700000000)
    }

    // MARK: - Value semantics

    @Test func equalDates_areEqualAndHashEqual() {
        let a = EpochSecondsDate(Date(timeIntervalSince1970: 42))
        let b = EpochSecondsDate(Date(timeIntervalSince1970: 42))
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func valueAndDateAccessorsReturnWrappedDate() {
        let date = Date(timeIntervalSince1970: 123456)
        let sut = EpochSecondsDate(date)
        #expect(sut.date == date)
        #expect(sut.value == date)
    }

    // MARK: - Within a container (the real usage: a date field on a ContentState)

    private struct State: Codable, Hashable {
        let title: String
        let eta: EpochSecondsDate
    }

    @Test func encodesAsBareNumberWithinContainer() throws {
        let state = State(title: "On the way", eta: EpochSecondsDate(Date(timeIntervalSince1970: 1609459200)))
        let object = try JSONSerialization.jsonObject(with: encoder.encode(state)) as? [String: Any]
        #expect((object?["eta"] as? NSNumber)?.int64Value == 1609459200)
    }

    @Test func decodesFromBareNumberWithinContainer() throws {
        let json = Data(#"{"title":"On the way","eta":1609459200}"#.utf8)
        let state = try decoder.decode(State.self, from: json)
        #expect(state.title == "On the way")
        #expect(state.eta.date == Date(timeIntervalSince1970: 1609459200))
    }
}
