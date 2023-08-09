import Foundation
#if canImport(UIKit)
import UIKit

public extension UIApplication {
    // since some extension functions may be able to run in iOS app extensions, only disable for this 1 function
    @available(iOSApplicationExtension, unavailable)
    func open(url: URL) {
        open(url, options: [:]) { _ in }
    }
}

public extension UIViewController {
    var moduleNameOfView: String? {
        Bundle(for: type(of: self)).bundleIdentifier
    }

    var isSwiftUIView: Bool {
        moduleNameOfView == "com.apple.SwiftUI"
    }
}

#endif
