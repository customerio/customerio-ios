import Foundation
#if canImport(UIKit)
import UIKit

public extension UIApplication {
    func open(url: URL) {
        if #available(iOS 10.0, *) {
            self.open(url, options: [:]) { _ in }
        } else {
            _ = openURL(url)
        }
    }
}

#endif
