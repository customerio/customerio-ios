import Foundation
import UIKit

class DeepLinkViewController: UIViewController {
    static func newInstance() -> DeepLinkViewController {
        UIStoryboard.getViewController(identifier: "DeepLinkViewController")
    }
}
