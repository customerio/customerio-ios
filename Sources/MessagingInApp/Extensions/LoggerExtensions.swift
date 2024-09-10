import CioInternalCommon
import Foundation

extension Logger {
    /// Logs a message with the `[InApp]` tag, appending it to the log message.
    /// This method is specific to the In-App module, where all log messages will be prefixed with `[InApp]`.
    ///
    /// - Parameters:
    ///   - message: The log message to be displayed.
    ///   - level: The log level (e.g., `.info`, `.debug`, `.error`).
    func logWithModuleTag(_ message: String, level: CioLogLevel) {
        let formattedMessage = "[InApp] \(message)"
        switch level {
        case .info:
            info(formattedMessage)
        case .debug:
            debug(formattedMessage)
        case .error:
            error(formattedMessage)
        case .none:
            break
        }
    }
}
