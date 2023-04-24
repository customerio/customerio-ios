import CioTracking
import Foundation

class EnvironmentUtil {
    static var cioSdkVersion: String {
        // TODO: expose SdkVersion in CIO SDK
        "(unknown)"
//        SdkVersion.version
    }

    static var appBuildVersion: String {
        Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
    }

    static var appBuildNumber: String {
        Bundle.main.infoDictionary!["CFBundleVersion"] as! String
    }
}
