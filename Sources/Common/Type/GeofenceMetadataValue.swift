import Foundation

/// A single value in a geofence's `metadata` map. Values are JSON scalars only (metadata are
/// flat, no nesting); the primitive type is preserved through decode → persistence → event payload so
/// campaign matching stays type-consistent (a numeric `priority` goes out as a number, not a string).
public enum GeofenceMetadataValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)

    /// The native Swift value, for building `[String: Any]` event properties.
    public var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Order matters: Bool before Int so JSON `true`/`false` isn't coerced to a number; Int before
        // Double so whole numbers stay integers; String last as the catch-all.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported metadata value (expected string, number, or bool)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}
