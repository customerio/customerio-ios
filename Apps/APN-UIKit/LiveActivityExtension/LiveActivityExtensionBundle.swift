import SwiftUI
import WidgetKit

/// Widget bundle for the sample app's Live Activities.
///
/// A customer registers their own `Widget` implementations here. The Customer.io SDK does not
/// render Live Activities — it only handles registration, push tokens, and lifecycle reporting —
/// so this file (and the widget it lists) is entirely app-owned.
@main
struct LiveActivityExtensionBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            DeliveryActivityWidget()
        }
    }
}
