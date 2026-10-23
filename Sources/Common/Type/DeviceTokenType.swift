import Foundation

/// Kind of device identifier Firebase gave the app.
/// Only known for values the SDK fetched from Firebase itself. APNs tokens and tokens passed to
/// `registerDeviceToken` have no type.
public enum DeviceTokenType: String, Codable {
    /// Legacy FCM registration token.
    case token
    /// Firebase Installation ID.
    case fid
}
