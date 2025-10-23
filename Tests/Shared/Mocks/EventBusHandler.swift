import CioInternalCommon
import Foundation

/// Mock of the EventBusHandler class, designed to mimic AutoMockable
/// Once the class is generated using AutoMockable, it should seamlessly replace the current implementation without any issues
public final class EventBusHandlerMock: EventBusHandler, Mock {
    /// Thread-safe storage for tracking mock invocations
    private struct MockData {
        var mockCalled = false
        var loadEventsFromStorageCallsCount = 0
        var addObserverCallsCount = 0
        var removeObserverCallsCount = 0
        var postEventCallsCount = 0
        var removeFromStorageCallsCount = 0
        var removeAllObserversCallsCount = 0
        var postEventArguments: (any EventRepresentable)?
        var postEventReceivedInvocations: [any EventRepresentable] = []
        var removeAllObserversClosure: (() -> Void)?
    }

    private let storage = ThreadSafeBoxedValue(MockData())

    public var mockCalled: Bool { storage.withValue { $0.mockCalled } }
    public var loadEventsFromStorageCallsCount: Int { storage.withValue { $0.loadEventsFromStorageCallsCount } }
    public var loadEventsFromStorageCalled: Bool { loadEventsFromStorageCallsCount > 0 }
    public var addObserverCallsCount: Int { storage.withValue { $0.addObserverCallsCount } }
    public var addObserverCalled: Bool { addObserverCallsCount > 0 }
    public var removeObserverCallsCount: Int { storage.withValue { $0.removeObserverCallsCount } }
    public var removeObserverCalled: Bool { removeObserverCallsCount > 0 }
    public var postEventCallsCount: Int { storage.withValue { $0.postEventCallsCount } }
    public var postEventCalled: Bool { postEventCallsCount > 0 }
    public var postEventArguments: (any EventRepresentable)? { storage.withValue { $0.postEventArguments } }
    public var postEventReceivedInvocations: [any EventRepresentable] { storage.withValue { $0.postEventReceivedInvocations } }
    public var removeFromStorageCallsCount: Int { storage.withValue { $0.removeFromStorageCallsCount } }
    public var removeFromStorageCalled: Bool { removeFromStorageCallsCount > 0 }
    public var removeAllObserversCallsCount: Int { storage.withValue { $0.removeAllObserversCallsCount } }
    public var removeAllObserversCalled: Bool { removeAllObserversCallsCount > 0 }

    public var removeAllObserversClosure: (() -> Void)? {
        get { storage.withValue { $0.removeAllObserversClosure } }
        set { storage.withValue { $0.removeAllObserversClosure = newValue } }
    }

    public init() {
        Mocks.shared.add(mock: self)
    }

    /// Thread-safe access to mutate mock tracking data
    private func withMockData(_ body: (inout MockData) -> Void) {
        storage.withValue(body)
    }

    public func resetMock() {
        withMockData { $0 = MockData() }
    }

    public func loadEventsFromStorage() async {
        withMockData {
            $0.mockCalled = true
            $0.loadEventsFromStorageCallsCount += 1
        }
    }

    public func addObserver<E>(_ eventType: E.Type, action: @escaping @Sendable (E) -> Void) where E: CioInternalCommon.EventRepresentable {
        withMockData {
            $0.mockCalled = true
            $0.addObserverCallsCount += 1
        }
    }

    public func removeObserver<E>(for eventType: E.Type) where E: CioInternalCommon.EventRepresentable {
        withMockData {
            $0.mockCalled = true
            $0.removeObserverCallsCount += 1
        }
    }

    public func postEvent<E: EventRepresentable>(_ event: E) {
        withMockData {
            $0.mockCalled = true
            $0.postEventCallsCount += 1
            $0.postEventArguments = event
            $0.postEventReceivedInvocations.append(event)
        }
    }

    public func postEventAndWait<E>(_ event: E) async where E: EventRepresentable {
        postEvent(event)
    }

    public func removeFromStorage<E>(_ event: E) async where E: CioInternalCommon.EventRepresentable {
        withMockData {
            $0.mockCalled = true
            $0.removeFromStorageCallsCount += 1
        }
    }

    public func removeAllObservers() {
        withMockData {
            $0.mockCalled = true
            $0.removeAllObserversCallsCount += 1
        }
        // Read the closure after updating counts
        let closure = storage.withValue { $0.removeAllObserversClosure }
        closure?()
    }
}
