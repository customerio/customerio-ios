import Foundation
import Security

/// Generates [ULID](https://github.com/ulid/spec) identifiers for locally-minted
/// Live Notification instances.
///
/// A ULID is a 128-bit, lexicographically sortable identifier:
/// - the most-significant 48 bits are a Unix-epoch **millisecond** timestamp, and
/// - the remaining 80 bits are cryptographic randomness.
///
/// It is rendered as a 26-character, **UPPERCASE** Crockford Base32 string. The first
/// 10 characters encode the timestamp and the last 16 encode the randomness. Because
/// `26 * 5 = 130` bits but the value is only 128 bits, the leading character carries just
/// 3 significant timestamp bits, so it is always in the range `0`–`7`.
///
/// The output is not lowercased: Crockford Base32 is case-insensitive on decode, but the
/// canonical form is uppercase and the backend expects the canonical form.
enum ULID {
    /// Crockford Base32 alphabet (excludes `I`, `L`, `O`, and `U` to avoid ambiguity).
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Generate a new ULID string for the given instant (defaults to now).
    ///
    /// - Parameter date: The instant whose millisecond timestamp seeds the first 48 bits.
    /// - Returns: A 26-character uppercase Crockford Base32 ULID.
    static func generate(date: Date = Date()) -> String {
        let milliseconds = timestampMilliseconds(from: date)
        return encodeTimestamp(milliseconds) + encodeRandomness(randomBytes())
    }

    // MARK: - Timestamp

    /// Clamp the date's millisecond timestamp into the representable 48-bit ULID range.
    private static func timestampMilliseconds(from date: Date) -> UInt64 {
        let millis = date.timeIntervalSince1970 * 1000
        guard millis > 0 else { return 0 }
        let maxTimestamp = (UInt64(1) << 48) - 1
        return min(UInt64(millis), maxTimestamp)
    }

    /// Encode the 48-bit timestamp as the first 10 Crockford Base32 characters,
    /// most-significant 5-bit group first.
    private static func encodeTimestamp(_ timestamp: UInt64) -> String {
        var characters = [Character]()
        characters.reserveCapacity(10)
        for index in 0 ..< 10 {
            let shift = UInt64((9 - index) * 5)
            let value = Int((timestamp >> shift) & 0x1F)
            characters.append(alphabet[value])
        }
        return String(characters)
    }

    // MARK: - Randomness

    /// 10 cryptographically random bytes (80 bits) from `SecRandomCopyBytes`.
    ///
    /// A non-`errSecSuccess` result falls back to `arc4random_buf` rather than throwing, so
    /// id generation never fails at the call site.
    private static func randomBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 10)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            arc4random_buf(&bytes, bytes.count)
        }
        return bytes
    }

    /// Encode 10 random bytes (80 bits) as the last 16 Crockford Base32 characters.
    ///
    /// The bytes are read as one big-endian bit stream split into 16 groups of 5 bits; no
    /// padding is required because `16 * 5 == 80`.
    private static func encodeRandomness(_ bytes: [UInt8]) -> String {
        var characters = [Character]()
        characters.reserveCapacity(16)
        for group in 0 ..< 16 {
            var value = 0
            for offset in 0 ..< 5 {
                let bitIndex = group * 5 + offset
                let bit = (bytes[bitIndex / 8] >> (7 - (bitIndex % 8))) & 1
                value = (value << 1) | Int(bit)
            }
            characters.append(alphabet[value])
        }
        return String(characters)
    }

    // MARK: - Decoding (test support)

    /// Decode the millisecond timestamp from the first 10 characters of a ULID.
    ///
    /// - Returns: The 48-bit timestamp, or `nil` if `ulid` is malformed.
    static func timestampMilliseconds(from ulid: String) -> UInt64? {
        guard ulid.count == 26 else { return nil }
        var timestamp: UInt64 = 0
        for character in ulid.prefix(10) {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            timestamp = (timestamp << 5) | UInt64(value)
        }
        return timestamp
    }
}
