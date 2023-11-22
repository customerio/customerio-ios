import Foundation

public class DIGraphShared: DIManager {
    public static let shared: DIGraphShared = .init()

    public var singletons: [String: Any] = [:]
    public var overrides: [String: Any] = [:]
}
