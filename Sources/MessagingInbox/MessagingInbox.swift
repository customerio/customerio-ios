import CioInternalCommon
import CioMessagingInApp
import Foundation

/// Namespace for the opt-in Visual Notification Inbox module.
///
/// This module renders a visual inbox (floating button, unread badge, slide-out panel)
/// on top of the existing headless inbox API exposed via `MessagingInApp.shared.inbox`.
///
/// This is the empty skeleton (Milestone 1, Work Unit 1): it establishes the SPM target,
/// CocoaPods spec, and resource bundle so the package and pod resolve and build. The public
/// SwiftUI UI (`NotificationInboxView` and its view model) lands in the next change.
enum MessagingInbox {}
