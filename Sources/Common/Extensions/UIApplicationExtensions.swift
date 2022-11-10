import Foundation
#if canImport(UIKit)
import UIKit

public extension UIApplication {
    @available(iOSApplicationExtension, unavailable) // since some extension functions may be able to run in iOS app extensions, only disable for this 1 function
    func open(url: URL) {
        open(url, options: [:]) { _ in }
    }
}

#endif
