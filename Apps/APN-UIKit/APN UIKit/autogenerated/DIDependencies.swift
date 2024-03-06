import Foundation

// sourcery: InjectRegisterShared = "UserDefaults"
// sourcery: InjectCustomShared
extension UserDefaults {}

extension DIGraphShared {
    var customUserDefaults: UserDefaults {
        UserDefaults.standard
    }
}
