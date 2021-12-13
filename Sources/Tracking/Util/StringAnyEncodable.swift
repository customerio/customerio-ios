import Foundation

public struct StringAnyEncodable: Encodable {
    private let data: [String:AnyEncodable]

    public init(_ data: [String:Any]) {
        var d = [String:AnyEncodable]()
        for (k, v) in data {
            switch v{
            case let enc as Encodable:
                d[k] = AnyEncodable(enc)
            case let dict as [String:Any]:
                d[k] = AnyEncodable(StringAnyEncodable(dict))
            default:
                // XXX: logger error
                continue
            }
        }
        self.data = d
    }

    public func encode(to encoder: Encoder) throws {
        try self.data.encode(to: encoder)
    }
}
