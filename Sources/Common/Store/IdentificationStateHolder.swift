import Foundation

// sourcery: InjectRegisterShared = "IdentificationStateHolder"
// sourcery: InjectSingleton
/// Holds the current identification state. Only **ProfileIdentifiedEvent** means identified (userId).
/// **AnonymousProfileIdentifiedEvent** and **ResetEvent** mean not identified.
/// Subscribes to those events on init so that after the first access (e.g. from DataPipeline or Location), state stays updated.
public final class IdentificationStateHolder: IdentificationStateProviding {
    @Atomic private var identified: Bool = false
    private let eventBusHandler: EventBusHandler

    public var isIdentified: Bool {
        identified
    }

    public init(eventBusHandler: EventBusHandler) {
        self.eventBusHandler = eventBusHandler
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { [weak self] _ in
            self?.setIdentified(true)
        }
        eventBusHandler.addObserver(AnonymousProfileIdentifiedEvent.self) { [weak self] _ in
            self?.setIdentified(false)
        }
        eventBusHandler.addObserver(ResetEvent.self) { [weak self] _ in
            self?.setIdentified(false)
        }
    }

    private func setIdentified(_ value: Bool) {
        identified = value
    }
}
