import CoreLocation
import Foundation

/// What the granted location permission lets region monitoring observe. A visit recorded under one
/// level of access cannot vouch for a continuous stay once access drops below it: the region events
/// that would have ended it may no longer arrive.
struct GeofenceLocationAccess: Codable, Equatable, Sendable {
    enum Delivery: Int, Codable, Sendable {
        case none = 0
        case foregroundOnly = 1
        case background = 2
    }

    let delivery: Delivery
    /// Precise location. Region monitoring stops under approximate location.
    let fullAccuracy: Bool

    init(delivery: Delivery, fullAccuracy: Bool) {
        self.delivery = delivery
        self.fullAccuracy = fullAccuracy
    }

    init(status: CLAuthorizationStatus, fullAccuracy: Bool) {
        switch CoreLocationGeofenceMonitor.permissionTier(for: status) {
        case .backgroundDelivery: self.delivery = .background
        case .foregroundOnly: self.delivery = .foregroundOnly
        case .blocked: self.delivery = .none
        }
        self.fullAccuracy = fullAccuracy
    }

    /// Whether region events still reach the app while it is not in the foreground.
    var observesBackground: Bool {
        delivery == .background
    }

    /// This access as the app can use it. Background App Refresh is a separate switch from the
    /// permission: with it denied or restricted, Core Location does not deliver region events to
    /// an app in the background, so Always delivers no more than When In Use.
    func limited(backgroundRefreshAvailable: Bool) -> GeofenceLocationAccess {
        guard !backgroundRefreshAvailable, delivery == .background else { return self }
        return GeofenceLocationAccess(delivery: .foregroundOnly, fullAccuracy: fullAccuracy)
    }

    /// Whether this access observes less than `previous` did. A repeat or an increase is not.
    func isDowngrade(from previous: GeofenceLocationAccess) -> Bool {
        delivery.rawValue < previous.delivery.rawValue || (previous.fullAccuracy && !fullAccuracy)
    }

    /// Reduced accuracy exists from iOS 14; before it, every grant is precise.
    static func current(of manager: CLLocationManager) -> GeofenceLocationAccess {
        if #available(iOS 14.0, *) {
            return GeofenceLocationAccess(
                status: manager.authorizationStatus,
                fullAccuracy: manager.accuracyAuthorization == .fullAccuracy
            )
        }
        return GeofenceLocationAccess(status: CLLocationManager.authorizationStatus(), fullAccuracy: true)
    }
}
