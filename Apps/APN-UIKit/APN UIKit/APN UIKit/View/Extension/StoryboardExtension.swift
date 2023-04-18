import Foundation
import UIKit

extension UIStoryboard {
    static func getViewController<VC: UIViewController>(identifier: String) -> VC {
        // Performing a force cast here is safe because the only reason that the code
        // would crash is by a developer bug like a typo. As long as each screen of
        // the app is able to be viewed (meaning all ViewControllers were instantiated
        // successfully), then this code is safe. Using a force cast here is to avoid
        // the annoyance of deciding what to do when there is a developer bug.
        UIStoryboard(name: "Main", bundle: nil)
            // swiftlint:disable:next force_cast
            .instantiateViewController(withIdentifier: identifier) as! VC
    }
}
