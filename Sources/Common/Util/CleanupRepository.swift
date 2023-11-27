import Foundation

public protocol CleanupRepository: AutoMockable {
    func cleanup()
}
