import CioInternalCommon
import Foundation

public protocol InAppEventListener: AutoMockable {
    func messageShown(message: InAppMessage)
    func messageDismissed(message: InAppMessage)
    func errorWithMessage(message: InAppMessage)
    // The generated mock derives its member names from the method's base name, so an overload would
    // collide with `errorWithMessage(message:)`. This names the mock's members instead.
    // sourcery: Name = "errorWithMessageAndError"
    /// Called when a message fails to load or render, with the reason it failed.
    ///
    /// Prefer this over ``errorWithMessage(message:)``. Branch on ``InAppMessageError/reason``;
    /// ``InAppMessageError/detail`` is diagnostic text meant for logs, not for parsing.
    func errorWithMessage(message: InAppMessage, error: InAppMessageError)
    func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String)
}

public extension InAppEventListener {
    /// Defaulted so listeners written before the reason existed keep compiling and keep working.
    func errorWithMessage(message: InAppMessage, error: InAppMessageError) {
        errorWithMessage(message: message)
    }
}
