import CioInternalCommon
import Foundation

/// Mock of the EventBusHandler class, designed to mimic AutoMockable
/// Once the class is generated using AutoMockable, it should seamlessly replace the current implementation without any issues
public actor EventBusHandlerMock: EventBusHandler, Mock {
    /// Thread-safe storage for tracking mock invocations
    private struct MockData {
        var mockCalled = false
        var trackTaskCallsCount = 0
        var loadEventsFromStorageCallsCount = 0
        var addObserverCallsCount = 0
        var removeObserverCallsCount = 0
        var postEventCallsCount = 0
        var removeFromStorageCallsCount = 0
        var postEventArguments: (any EventRepresentable)?
    }

    private let concurrency: ConcurrencySupport
    private let storage = ThreadSafeBoxedValue(MockData())

    public nonisolated var mockCalled: Bool { storage.withValue { $0.mockCalled } }
    public nonisolated var trackTaskCallsCount: Int { storage.withValue { $0.trackTaskCallsCount } }
    public nonisolated var loadEventsFromStorageCallsCount: Int { storage.withValue { $0.loadEventsFromStorageCallsCount } }
    public nonisolated var addObserverCallsCount: Int { storage.withValue { $0.addObserverCallsCount } }
    public nonisolated var removeObserverCallsCount: Int { storage.withValue { $0.removeObserverCallsCount } }
    public nonisolated var postEventCallsCount: Int { storage.withValue { $0.postEventCallsCount } }
    public nonisolated var removeFromStorageCallsCount: Int { storage.withValue { $0.removeFromStorageCallsCount } }
    public nonisolated var postEventArguments: (any EventRepresentable)? { storage.withValue { $0.postEventArguments } }

    public nonisolated var trackTaskCalled: Bool { trackTaskCallsCount > 0 }
    public nonisolated var loadEventsFromStorageCalled: Bool { loadEventsFromStorageCallsCount > 0 }
    public nonisolated var addObserverCalled: Bool { addObserverCallsCount > 0 }
    public nonisolated var removeObserverCalled: Bool { removeObserverCallsCount > 0 }
    public nonisolated var postEventCalled: Bool { postEventCallsCount > 0 }
    public nonisolated var removeFromStorageCalled: Bool { removeFromStorageCallsCount > 0 }

    public init(concurrency: ConcurrencySupport = DIGraphShared.shared.concurrencySupport) {
        self.concurrency = concurrency
        Mocks.shared.add(mock: self)
    }

    /// Thread-safe access to mutate mock tracking data
    private nonisolated func withMockData(_ body: (inout MockData) -> Void) {
        storage.withValue(body)
    }

    public nonisolated func resetMock() {
        withMockData { $0 = MockData() }
    }

    @discardableResult
    public nonisolated func dispatch(
        _ operation: @Sendable @escaping (isolated EventBusHandler) async -> Void
    ) -> Task<Void, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        let task = concurrency.execute(on: self) {
            await operation($0)
            semaphore.signal()
        }
        concurrency.execute(on: self) {
            $0.disposeWithLifecycle(task)
        }

        let timeout = DispatchTime.now() + .seconds(5)
        let result = semaphore.wait(timeout: timeout)

        if result == .timedOut {
            DIGraphShared.shared.logger.error("EventBusHandlerMock: Operation timed out after 5 seconds")
        }

        return task
    }

    public func disposeWithLifecycle(_ task: Task<Void, Error>) {
        withMockData {
            $0.mockCalled = true
            $0.trackTaskCallsCount += 1
        }
    }

    public func loadEventsFromStorage() async {
        withMockData {
            $0.mockCalled = true
            $0.loadEventsFromStorageCallsCount += 1
        }
    }

    public func addObserver<E>(_ eventType: E.Type, action: @escaping @Sendable (E) -> Void) async where E: CioInternalCommon.EventRepresentable {
        withMockData {
            $0.mockCalled = true
            $0.addObserverCallsCount += 1
        }
    }

    public func removeObserver<E>(for eventType: E.Type) async where E: CioInternalCommon.EventRepresentable {
        withMockData {
            $0.mockCalled = true
            $0.removeObserverCallsCount += 1
        }
    }

    public func postEvent<E: EventRepresentable>(_ event: E) async {
        withMockData {
            $0.mockCalled = true
            $0.postEventCallsCount += 1
            $0.postEventArguments = event
        }
    }

    public func removeFromStorage<E>(_ event: E) async where E: CioInternalCommon.EventRepresentable {
        withMockData {
            $0.mockCalled = true
            $0.removeFromStorageCallsCount += 1
        }
    }
}
