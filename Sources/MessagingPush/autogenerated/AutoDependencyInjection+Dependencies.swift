import CioTracking
import Foundation

/// If a dependency in `DIMessagingPush` needs to access a dependency from the `DITracking` graph,
/// this hack allows that. Use this extension like this:
/// ```
/// internal class CioPushDeviceTokenRepository: PushDeviceTokenRepository {
///   internal init(diTracking: DITracking) {
///     self.profileStore = diTracking.profileStore
///   }
/// }
/// ```
extension DIMessagingPush {
    var dITracking: DITracking {
        DITracking.getInstance(siteId: siteId)
    }
}
