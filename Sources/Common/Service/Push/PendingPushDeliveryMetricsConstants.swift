import Foundation

enum PendingPushDeliveryMetricsConstants {
    /// Maximum pending metrics kept in app group storage; oldest entries are removed when appending beyond this limit.
    static let maxEntries = 100

    static let storageSubdirectoryName = "io.customer"
    static let storageFileName = "pending_push_delivery_metrics.json"
}
