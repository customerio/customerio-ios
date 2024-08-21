import Foundation

class UserManager {
    let userTokenKey = "UserToken"
    let defaults = UserDefaults.standard

    func getUserToken() -> String? {
        defaults.string(forKey: userTokenKey)
    }

    func setUserToken(userToken: String) {
        Logger.instance.info(message: "User token set: \(userToken)")
        defaults.set(userToken, forKey: userTokenKey)
    }

    func clearUserToken() {
        Logger.instance.info(message: "User token cleared")
        defaults.removeObject(forKey: userTokenKey)
    }
}
