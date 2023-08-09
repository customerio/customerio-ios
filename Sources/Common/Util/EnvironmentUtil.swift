import Foundation
import SwiftUI

// Provides information about the environment the SDK is running inside of.
@available(iOSApplicationExtension, unavailable)
public protocol EnvironmentUtil: AutoMockable {
    var isSwiftUIApp: Bool { get }
}

@available(iOSApplicationExtension, unavailable) // this is added because of UIKitWrapper depencency
// sourcery: InjectRegister = "EnvironmentUtil"
public class EnvironmentUtilImpl: EnvironmentUtil {
    private let uiKit: UIKitWrapper

    public init(uiKit: UIKitWrapper) {
        self.uiKit = uiKit
    }

    // At runtime, we can detect if the iOS app is a SwiftUI application because SwiftUI uses a wrapper around some UIKit classes. By seeing if the AppDelegate is provided by SwiftUI, then we know the AppDelegate is being wrapped.
    public var isSwiftUIApp: Bool {
        #if canImport(SwiftUI)

        guard let uiApplication = uiKit.uiApplication, let delegate = uiApplication.delegate else {
            return false
        }

        // The description will contain module name "SwiftUI" if the class belongs to that module.
        // We must use a string because 'SwiftUI.AppDelegate' is not public so we cannot do something such as: `delegate is SwiftUI.AppDelegate`
        return delegate.description.contains("SwiftUI.")

        #else
        return false
        #endif
    }
}
