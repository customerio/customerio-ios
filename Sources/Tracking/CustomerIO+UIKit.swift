import Foundation
#if canImport(UIKit)
import UIKit

public extension CustomerIO {
    func setupScreenViewTracking() {
        UIViewController.swizzleScreenViews(customerIO: self)
    }
}

#endif
