import CioInternalCommon
import Foundation

protocol PushHistory: AutoMockable {
    /**
     Thread-safe method to check if a push event has been handled before.

     If the push has not been handled before, it will be marked as handled. This is to prevent race conditions. Code such as this may have a race condition bug that we want to prevent:

     ```
     let hasPushBeenHandled = pushHistory.hasHandledPush(pushId)
     if !hasPushBeenHandled {
       pushHistory.markPushAsHandled(pushId)
     }
     ```
     By having 1 thread-safe function perform the check and mark, we can prevent this scenario.

     @return true if push has been handled before. false otherwise.
     */
    func hasHandledPush(pushEvent: PushHistoryEvent, pushId: String) -> Bool
}

enum PushHistoryEvent {
    case didReceive
    case willPresent
}

// sourcery: InjectRegister = "PushHistory"
class PushHistoryImpl: PushHistory {
    private let keyValueStorage: KeyValueStorage
    private let lock: Lock

    var maxSizeOfHistory = 100

    init(keyValueStorage: KeyValueStorage, lockManager: LockManager) {
        self.keyValueStorage = keyValueStorage
        self.lock = lockManager.getLock(id: .pushHistory)
    }

    func hasHandledPush(pushEvent: PushHistoryEvent, pushId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let hasHandledAlready = getHistory(for: pushEvent).contains(pushId)

        if hasHandledAlready {
            return true // push has already been handled. exit early
        }

        markEventAsHandled(pushId: pushId, event: pushEvent)

        return false // push has not yet been handled.
    }
}

extension PushHistoryImpl {
    private func markEventAsHandled(pushId: String, event: PushHistoryEvent) {
        lock.lock()
        defer { lock.unlock() }

        var clickHistory = getHistory(for: event)

        if clickHistory.count >= maxSizeOfHistory {
            // Remove oldest push click from history.
            clickHistory = Array(clickHistory.dropFirst())
        }

        clickHistory.append(pushId)

        setHistory(clickHistory, forEvent: event)
    }

    private func getKeyValueStorageKey(forEvent event: PushHistoryEvent) -> KeyValueStorageKey {
        switch event {
        case .didReceive:
            return .pushNotificationsHandledDidReceive
        case .willPresent:
            return .pushNotificationsHandledWillPresent
        }
    }

    private func getHistory(for event: PushHistoryEvent) -> [String] {
        let stringRepresentationOfArray = keyValueStorage.string(getKeyValueStorageKey(forEvent: event)) ?? ""

        return stringRepresentationOfArray.split(separator: ",").map { String($0) }
    }

    private func setHistory(_ history: [String], forEvent event: PushHistoryEvent) {
        let stringRepresentationOfArray = history.joined(separator: ",")
        keyValueStorage.setString(stringRepresentationOfArray, forKey: getKeyValueStorageKey(forEvent: event))
    }
}
