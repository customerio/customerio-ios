import CioInternalCommon
import Foundation

protocol PushHistory: AutoMockable {
    func hasHandledPushClick(deliveryId: String) -> Bool
    func handledPushClick(deliveryId: String)
}

// sourcery: InjectRegister = "PushHistory"
class PushHistoryImpl: PushHistory {
    private let keyValueStorage: KeyValueStorage

    var numberOfPushesToTrack = 100

    var lastPushesClicked: [String] {
        get {
            let stringRepresentationOfArray = keyValueStorage.string(.pushNotificationsClicked) ?? ""

            return stringRepresentationOfArray.split(separator: ",").map { String($0) }
        }
        set {
            let stringRepresentationOfArray = newValue.joined(separator: ",")
            keyValueStorage.setString(stringRepresentationOfArray, forKey: .pushNotificationsClicked)
        }
    }

    init(keyValueStorage: KeyValueStorage) {
        self.keyValueStorage = keyValueStorage
    }

    func hasHandledPushClick(deliveryId: String) -> Bool {
        lastPushesClicked.contains(deliveryId)
    }

    func handledPushClick(deliveryId: String) {
        var clickHistory = lastPushesClicked

        if clickHistory.count >= numberOfPushesToTrack {
            // Remove oldest push click from history.
            clickHistory = Array(clickHistory.dropFirst())
        }

        clickHistory.append(deliveryId)

        lastPushesClicked = clickHistory
    }
}
