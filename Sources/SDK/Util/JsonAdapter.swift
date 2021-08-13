import Foundation

internal enum JsonAdpter {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func fromJson<T: Decodable>(_ json: Data) throws -> T {
        try decoder.decode(T.self, from: json)
    }

    static func toJson<T: Encodable>(_ obj: T) throws -> Data {
        try encoder.encode(obj)
    }
}
