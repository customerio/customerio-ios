import CioInternalCommon
import Foundation

protocol PushHistory: AutoMockable {
    func hasHandledPushClick(deliveryId: String) -> Bool
    func handledPushClick(deliveryId: String)
}

// sourcery: InjectRegister = "PushHistory"
class PushHistoryImpl: PushHistory {
    private let keyValueStorage: KeyValueStorage
    private let lock: Lock

    var maxSizeOfHistory = 100

    // internal getter for tests to access
    private(set) var lastPushesClicked: [String] {
        get {
            let stringRepresentationOfArray = keyValueStorage.string(.pushNotificationsClicked) ?? ""

            return stringRepresentationOfArray.split(separator: ",").map { String($0) }
        }
        set {
            let stringRepresentationOfArray = newValue.joined(separator: ",")
            keyValueStorage.setString(stringRepresentationOfArray, forKey: .pushNotificationsClicked)
        }
    }

    init(keyValueStorage: KeyValueStorage, lockManager: LockManager) {
        self.keyValueStorage = keyValueStorage
        self.lock = lockManager.getLock(id: .pushHistory)
    }

    func hasHandledPushClick(deliveryId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return lastPushesClicked.contains(deliveryId)
    }

    func handledPushClick(deliveryId: String) {
        lock.lock()
        defer { lock.unlock() }

        var clickHistory = lastPushesClicked

        if clickHistory.count >= maxSizeOfHistory {
            // Remove oldest push click from history.
            clickHistory = Array(clickHistory.dropFirst())
        }

        clickHistory.append(deliveryId)

        lastPushesClicked = clickHistory
    }
}
