import CioInternalCommon
import CioMessagingInApp
import Foundation

/// Namespace for the opt-in Visual Notification Inbox module.
///
/// This module renders a visual inbox (floating button, unread badge, slide-out panel)
/// on top of the existing headless inbox API exposed via `MessagingInApp.shared.inbox`.
///
/// The public entry point is ``NotificationInboxView``, a SwiftUI view customers can mount
/// anywhere in their view hierarchy. It overlays a floating button with an unread badge; tapping
/// it reveals a slide-out panel listing inbox messages. The whole UI hides itself when there are
/// no messages.
enum MessagingInbox {}
