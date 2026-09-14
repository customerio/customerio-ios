import CioInternalCommon
import Foundation

/// A clock a test can move.
///
/// `givenNow` is written from the test thread and read from wherever the code under test happens to
/// ask the time — a detached task, an actor, or a `@MainActor` type. `GeofenceStorage` is an actor
/// that holds a `DateUtil`, and the same stub instance is commonly handed both to it and to the
/// main-actor monitor, so a plain stored property here is a data race across two isolation domains.
/// Guarding the storage keeps every existing call site (65 of them) working unchanged.
public class DateUtilStub: DateUtil {
    // Important that we create a Date with milliseconds as that is what
    // the real implmentation of DateUtil will use. Do not remove milliseconds here.
    private let storedNow = Synchronized<Date>(Date())

    public var givenNow: Date {
        get { storedNow.wrappedValue }
        set { storedNow.wrappedValue = newValue }
    }

    public init() {}

    public var now: Date {
        givenNow
    }
}

public extension DateUtilStub {
    // Convenient way to get seconds (removed milliseconds) in tests.
    // Common to use when testing Json since our JsonAdapter removes milliseconds when composing Json strings.
    var nowSeconds: Int {
        Int(now.timeIntervalSince1970)
    }
}
