import Foundation

internal enum JsonAdpter {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601)
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601)
        return encoder
    }

    static func fromJson<T: Decodable>(_ json: Data) throws -> T {
        try decoder.decode(T.self, from: json)
    }

    static func toJson<T: Encodable>(_ obj: T) throws -> Data {
        try encoder.encode(obj)
    }
}
