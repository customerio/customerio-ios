import Foundation

internal extension Result {
    var error: Failure? {
        switch self {
        case .failure(let error): return error
        default: return nil
        }
    }

    var success: Success? {
        switch self {
        case .success(let success): return success
        default: return nil
        }
    }
}
