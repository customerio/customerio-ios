import Foundation

// sourcery: InjectRegister = "UserDefaults"
// sourcery: InjectCustom
extension UserDefaults {}

extension DI {
    var customUserDefaults: UserDefaults {
        UserDefaults.standard
    }
}
