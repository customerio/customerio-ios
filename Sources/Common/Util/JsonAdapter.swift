import Foundation

public enum JsonAdapter {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    public static func fromJson<T: Decodable>(_ json: Data) -> T? {
        do {
            let value = try decoder.decode(T.self, from: json)
            return value
        } catch {
            return nil
        }
    }

    public static func toJson<T: Encodable>(_ obj: T) -> Data? {
        do {
            let value = try encoder.encode(obj)
            return value
        } catch {
            return nil
        }
    }
}
