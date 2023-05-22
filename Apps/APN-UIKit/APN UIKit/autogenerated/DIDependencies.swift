import Foundation

// sourcery: InjectRegister = "UserDefaults"
// sourcery: InjectCustom
extension UserDefaults {}

extension DIGraph {
    var customUserDefaults: UserDefaults {
        UserDefaults.standard
    }
}
