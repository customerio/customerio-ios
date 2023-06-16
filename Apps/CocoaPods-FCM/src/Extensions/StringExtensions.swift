import Foundation

extension String {
    static var alphaNumericCharacters: String {
        "abcdefghijklmnopqrstuvwxyz1234567890"
    }

    static func random(length: Int = 10) -> String {
        String((0 ..< length).map { _ in alphaNumericCharacters.randomElement()! })
    }
}
