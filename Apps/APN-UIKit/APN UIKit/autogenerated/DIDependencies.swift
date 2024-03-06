import Foundation

// sourcery: InjectRegisterShared = "UserDefaults"
// sourcery: InjectCustom
extension UserDefaults {}

extension DIGraphShared {
    var customUserDefaults: UserDefaults {
        UserDefaults.standard
    }
}
