import Foundation

// sourcery: InjectRegisterShared = "UserDefaults"
// sourcery: InjectCustomShared
// swiftformat:disable:next emptyExtensions
extension UserDefaults {}

extension DIGraphShared {
    var customUserDefaults: UserDefaults {
        UserDefaults.standard
    }
}
