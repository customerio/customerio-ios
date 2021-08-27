import Foundation

/**
 Convert between Swift structs and JSON strings and vice-versa.
 */
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

    /**
     Returns optional to be more convenient then try/catch all over the code base.

     It *should* be rare to have an issue with encoding and decoding JSON because the Customer.io API
     response formats are consistent and input data from the SDK functions are tied to a certain data
     type (if struct wants an Int, you can only pass an Int).

     The negative to this method is that we don't get to capture the `Error` to debug it if we don't
     expect to get an error. If we need this functionality, perhaps we should create a 2nd set of
     methods to this class that `throw` so you choose which function to use?
     */
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
