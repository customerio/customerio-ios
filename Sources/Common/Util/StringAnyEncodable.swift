import Foundation

public struct StringAnyEncodable: Encodable {
    private let data: [String: AnyEncodable]

    public init(_ data: [String: Any]) {
        func encode(value: Any) -> AnyEncodable? {
            switch value {
            case let enc as Encodable:
                return AnyEncodable(enc)
            
            case let dict as [String: Any]:
                return AnyEncodable(StringAnyEncodable(dict))
            
            case let list as [Any]:
                return AnyEncodable(list.compactMap { encode(value: $0) })

            default:
                // XXX: logger error
                return nil;
            }
        }

        self.data = data.compactMapValues { encode(value: $0) }
    }

    public func encode(to encoder: Encoder) throws {
        try data.encode(to: encoder)
    }
}
