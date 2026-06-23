import CioInternalCommon
import Foundation

extension Logger {
    /// Emits the visual-inbox terminal visibility decision with a `[CIO-Inbox]` prefix.
    /// When hidden, the reason carried by the state makes the gate outcome obvious in a
    /// sample-app log trace.
    func logVisualInboxVisibility(_ state: VisualInboxLoadState) {
        switch state {
        case .visible(let count):
            logWithModuleTag("[CIO-Inbox] final visibility decision: visible(\(count))", level: .info)
        case .hidden(let reason):
            logWithModuleTag("[CIO-Inbox] final visibility decision: hidden (\(reason))", level: .info)
        case .idle, .loading:
            logWithModuleTag("[CIO-Inbox] final visibility decision: \(state)", level: .debug)
        }
    }
}
