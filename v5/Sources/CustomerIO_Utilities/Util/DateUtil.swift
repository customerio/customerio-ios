import Foundation

/// Provides the current date. Inject a fixed-date mock in tests.
public protocol DateProviding: Sendable {
    var now: Date { get }
}

public struct SystemDateProvider: DateProviding, Sendable {
    public init() {}
    public var now: Date { Date() }
}
