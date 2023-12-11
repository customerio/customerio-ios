import Combine
import Foundation

/// Manages event subscriptions and handles storing and retrieving events from storage.
public class EventHandlingManager {
    public let eventBus: EventBus
    private let eventStorage: EventStorage
    private var subscriptions: Set<AnyCancellable> = []

    public init(eventBus: EventBus, eventStorage: EventStorage) {
        self.eventBus = eventBus
        self.eventStorage = eventStorage
    }

    /// Subscribes to `NewSubscriptionEvent` and loads and sends stored events for new subscriptions.
    /// - Parameter eventTypes: An array of event type keys to monitor for new subscriptions.
    public func handleNewSubscriptions(for eventTypes: [String]) {
        eventBus.onReceive(NewSubscriptionEvent.self) { [weak self] newSubEvent in
            guard let self = self else { return }
            if eventTypes.contains(newSubEvent.subscribedEventType) {
                self.loadAndSendStoredEvents(forTypeKey: newSubEvent.subscribedEventType)
            }
        }.store(in: &subscriptions)
    }

    /// Loads and sends stored events for a given event type key.
    /// - Parameter typeKey: The key representing the event type.
    private func loadAndSendStoredEvents(forTypeKey typeKey: String) {
        switch typeKey {
        case TrackMetricEvent.key:
            loadAndSendStoredEvents(ofType: TrackMetricEvent.self)
        case ProfileIdentifiedEvent.key:
            loadAndSendStoredEvents(ofType: ProfileIdentifiedEvent.self)
        case ScreenViewedEvent.key:
            loadAndSendStoredEvents(ofType: ScreenViewedEvent.self)
        case ResetEvent.key:
            loadAndSendStoredEvents(ofType: ResetEvent.self)
        case RegisterDeviceTokenEvent.key:
            loadAndSendStoredEvents(ofType: RegisterDeviceTokenEvent.self)
        case DeleteDeviceTokenEvent.key:
            loadAndSendStoredEvents(ofType: DeleteDeviceTokenEvent.self)
        case NewSubscriptionEvent.key:
            break
        default:
            break
        }
    }

    /// Generic method to load and send stored events of a specific type.
    /// - Parameter eventType: The type of event to load and send.
    private func loadAndSendStoredEvents<E: EventRepresentable>(ofType eventType: E.Type) {
        do {
            let key = eventType.key
            let storedEvents: [E] = try eventStorage.loadAllEvents(ofType: eventType, withKey: key)
            storedEvents.forEach { eventBus.send($0) }
        } catch {
            handleEventStorageError(error)
        }
    }

    /// Sends an event or stores it if there are no listeners.
    /// - Parameter event: The event to be sent or stored.
    public func sendOrSaveEvent(event: any EventRepresentable) {
        if eventBus.send(event) == false {
            let key = event.key
            do {
                try eventStorage.store(event: event, forKey: key)
            } catch {
                print("Error storing event: \(error)")
            }
        }
    }

    /// Handles errors that occur while loading stored events.
    /// - Parameter error: The error encountered during event loading.
    private func handleEventStorageError(_ error: Error) {
        // Implement error handling logic
        print("Error loading stored events: \(error)")
    }
}
