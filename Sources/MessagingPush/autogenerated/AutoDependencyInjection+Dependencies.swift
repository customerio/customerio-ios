import Common
import Foundation

/// If a dependency in `DIMessagingPush` needs to access a dependency from the `DITracking` graph,
/// this hack allows that. Use this extension like this:
/// ```
/// internal class CioPushDeviceTokenRepository: PushDeviceTokenRepository {
///   internal init(diTracking: DITracking) {
///     self.profileStore = dICommon.profileStore
///   }
/// }
/// ```
extension DIMessagingPush {
    var dICommon: DICommon {
        DICommon.getInstance(siteId: siteId)
    }
}
