import CioInternalCommon
import Foundation

protocol PushHistory: AutoMockable {
    func hasHandledPushDidReceive(pushId: String) -> Bool
    func didHandlePushDidReceive(pushId: String)

    func hasHandledPushWillPresent(pushId: String) -> Bool
    func didHandlePushWillPresent(pushId: String)
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

    func hasHandledPushDidReceive(pushId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return getHistory(for: .pushNotificationsHandledDidReceive).contains(pushId)
    }

    func hasHandledPushWillPresent(pushId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return getHistory(for: .pushNotificationsHandledWillPresent).contains(pushId)
    }

    func didHandlePushDidReceive(pushId: String) {
        sharedDidHandle(pushId: pushId, historyKey: .pushNotificationsHandledDidReceive)
    }

    func didHandlePushWillPresent(pushId: String) {
        sharedDidHandle(pushId: pushId, historyKey: .pushNotificationsHandledWillPresent)
    }
}

extension PushHistoryImpl {
    private func sharedDidHandle(pushId: String, historyKey: KeyValueStorageKey) {
        lock.lock()
        defer { lock.unlock() }

        var clickHistory = getHistory(for: historyKey)

        if clickHistory.count >= maxSizeOfHistory {
            // Remove oldest push click from history.
            clickHistory = Array(clickHistory.dropFirst())
        }

        clickHistory.append(pushId)

        setHistory(clickHistory, for: historyKey)
    }

    private func getHistory(for key: KeyValueStorageKey) -> [String] {
        let stringRepresentationOfArray = keyValueStorage.string(key) ?? ""

        return stringRepresentationOfArray.split(separator: ",").map { String($0) }
    }

    private func setHistory(_ history: [String], for key: KeyValueStorageKey) {
        let stringRepresentationOfArray = history.joined(separator: ",")
        keyValueStorage.setString(stringRepresentationOfArray, forKey: key)
    }
}
