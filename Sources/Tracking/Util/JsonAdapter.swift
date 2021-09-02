import Foundation

/**
 Convert between Swift structs and JSON strings and vice-versa.
 */
// sourcery: InjectRegister = "JsonAdapter"
public class JsonAdapter {
    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private let log: Logger

    init(log: Logger) {
        self.log = log
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
    public func fromJson<T: Decodable>(_ json: Data) -> T? {
        do {
            let value = try decoder.decode(T.self, from: json)
            return value
        } catch DecodingError.keyNotFound(let key, let context) {
            self.log
                .error("Decode key not found. Key: \(key), Json path: \(context.codingPath), json: \(json.string ?? "(error getting json string)")")
        } catch DecodingError.valueNotFound(let type, let context) {
            self.log
                .error("Decode non-optional value not found. Value: \(type), Json path: \(context.codingPath), json: \(json.string ?? "(error getting json string)")")
        } catch DecodingError.typeMismatch(let type, let context) {
            self.log
                .error("Decode type did not match payload. Type: \(type), Json path: \(context.codingPath), json: \(json.string ?? "(error getting json string)")")
        } catch DecodingError.dataCorrupted(let context) {
            self.log
                .error("Decode data corrupted. Json path: \(context.codingPath), json: \(json.string ?? "(error getting json string)")")
        } catch {
            log
                .error("Generic decide error. \(error.localizedDescription), json: \(json.string ?? "(error getting json string)")")
        }

        return nil
    }

    public func toJson<T: Encodable>(_ obj: T) -> Data? {
        do {
            let value = try encoder.encode(obj)
            return value
        } catch EncodingError.invalidValue(let value, let context) {
            self.log
                .error("Encoding could not encode value. \(value), Json path: \(context.codingPath), object: \(obj)")
        } catch {
            log.error("Generic encode error. \(error.localizedDescription), object: \(obj)")
        }

        return nil
    }
}
