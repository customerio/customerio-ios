@testable import CioInternalCommon
import Foundation

public extension HttpRequestError {
    static func getGenericFailure() -> HttpRequestError {
        // Choose an error that does not run certain logic in the code-base such as
        // HTTP requests being paused.
        .noRequestMade(nil)
    }
}
