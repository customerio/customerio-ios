import Foundation
#if canImport(UIKit)
import UIKit

public extension UIApplication {
    func open(url: URL) {
        open(url, options: [:]) { _ in }
    }
}

#endif
