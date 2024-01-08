import CioInternalCommon

class EventBusHandlerMock: EventBusHandler, Mock {
    public var mockCalled: Bool = false

    init() {
        Mocks.shared.add(mock: self)
    }

    func resetMock() {
        mockCalled = false
        loadEventsFromStorageCallsCount = 0
        addObserverCallsCount = 0
        removeObserverCallsCount = 0
        postEventCallsCount = 0
        removeFromStorageCallsCount = 0
    }

    public private(set) var loadEventsFromStorageCallsCount = 0
    public var loadEventsFromStorageCalled: Bool { loadEventsFromStorageCallsCount > 0 }

    func loadEventsFromStorage() async {
        mockCalled = true
        loadEventsFromStorageCallsCount += 1
    }

    public private(set) var addObserverCallsCount = 0
    public var addObserverCalled: Bool { loadEventsFromStorageCallsCount > 0 }

    func addObserver<E>(_ eventType: E.Type, action: @escaping (E) -> Void) where E: CioInternalCommon.EventRepresentable {
        mockCalled = true
        addObserverCallsCount += 1
    }

    public private(set) var removeObserverCallsCount = 0
    public var removeObserverCalled: Bool { loadEventsFromStorageCallsCount > 0 }

    func removeObserver<E>(for eventType: E.Type) where E: CioInternalCommon.EventRepresentable {
        mockCalled = true
        removeObserverCallsCount += 1
    }

    public private(set) var postEventCallsCount = 0
    public var postEventCalled: Bool { loadEventsFromStorageCallsCount > 0 }
    public private(set) var postEventArguments: (any EventRepresentable)?

    func postEvent<E: EventRepresentable>(_ event: E) {
        mockCalled = true
        postEventCallsCount += 1
        postEventArguments = event
    }

    public private(set) var removeFromStorageCallsCount = 0
    public var removeFromStorageCalled: Bool { loadEventsFromStorageCallsCount > 0 }

    func removeFromStorage<E>(_ event: E) async where E: CioInternalCommon.EventRepresentable {
        mockCalled = true
        removeFromStorageCallsCount += 1
    }
}