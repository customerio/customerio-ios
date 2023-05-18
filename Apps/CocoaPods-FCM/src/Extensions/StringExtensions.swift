import Foundation

extension String {
    static var abcLetters: String {
        "abcdefghijklmnopqrstuvwxyz"
    }

    static func random(length: Int = 10) -> String {
        String((0 ..< length).map { _ in abcLetters.randomElement()! })
    }
}
