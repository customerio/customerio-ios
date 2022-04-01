import Foundation

public struct StringAnyEncodable: Encodable {
    private let data: [String: AnyEncodable]

    public init(_ data: [String: Any]) {
        var builtValue = [String: AnyEncodable]()
        for (key, value) in data {
            switch value {
            case let enc as Encodable:
                builtValue[key] = AnyEncodable(enc)
            case let dict as [String: Any]:
                builtValue[key] = AnyEncodable(StringAnyEncodable(dict))
            default:
                // XXX: logger error
                continue
            }
        }
        self.data = builtValue
    }

    public func encode(to encoder: Encoder) throws {
        try data.encode(to: encoder)
    }
}
