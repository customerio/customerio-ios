import CioTracking
import Foundation

class EnvironmentUtil {
    static var cioSdkVersion: String {
        CustomerIO.version
    }

    static var appName: String {
        Bundle.main.infoDictionary!["CFBundleDisplayName"] as! String
    }

    static var appBuildVersion: String {
        Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
    }

    static var appBuildNumber: String {
        Bundle.main.infoDictionary!["CFBundleVersion"] as! String
    }
}
