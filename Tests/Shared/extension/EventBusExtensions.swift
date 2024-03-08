@testable import CioInternalCommon
import Foundation

/*
 Collection of EventBus functions only meant to be used for tests, not in SDK code.
 */

// MARK: wait for events to finish replaying.

// Replaying eventbus events is an async operation in the SDK. Some test functions may need to wait to proceed until after these async operations are complete.

public extension EventBusHandler {
    func waitForReplayEventsToFinish<E>(_ eventType: E.Type) async where E: EventRepresentable {
        await(self as? CioEventBusHandler)?.waitForReplayEventsToFinish(eventType)
    }
}

public extension CioEventBusHandler {
    func waitForReplayEventsToFinish<E>(_ eventType: E.Type) async where E: EventRepresentable {
        do {
            while true {
                let key = eventType.key
                let storedEvents = try await eventStorage.loadEvents(ofType: key)
                if storedEvents.isEmpty {
                    return
                }
            }
        } catch {
            logger.debug("Error waiting for relay events to finish: \(error)")
        }
    }
}
