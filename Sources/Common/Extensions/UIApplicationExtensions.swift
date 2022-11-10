import Foundation
#if canImport(UIKit)
import UIKit

public extension UIApplication {
    @available(iOSApplicationExtension, unavailable)
    func open(url: URL) {
        open(url, options: [:]) { _ in }
    }
}

#endif
