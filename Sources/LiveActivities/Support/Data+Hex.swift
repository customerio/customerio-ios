import Foundation

extension Data {
    /// Lowercase hex-string encoding of the bytes, used for APNs push tokens.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
