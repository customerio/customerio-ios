import Foundation

extension String {
    /// Encodes a specific character in the string using percent encoding.
    func percentEncode(character target: String, withAllowedCharacters allowedCharacters: CharacterSet = .urlPathAllowed) -> String {
        replacingOccurrences(of: target, with: target.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? target)
    }
}
