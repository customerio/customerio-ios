import Foundation

protocol JsonAdapter {
    var encoder: JSONEncoder { get }
    var decoder: JSONDecoder { get }

    func fromJson<T: Decodable>(_ json: Data) throws -> T
    func toJson<T: Encodable>(_ obj: T) throws -> Data
}

// sourcery: InjectRegister = "JsonAdapter"
class SwiftJsonAdpter: JsonAdapter {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    init() {
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601)
        encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601)
    }

    func fromJson<T: Decodable>(_ json: Data) throws -> T {
        try decoder.decode(T.self, from: json)
    }

    func toJson<T: Encodable>(_ obj: T) throws -> Data {
        try encoder.encode(obj)
    }
}
