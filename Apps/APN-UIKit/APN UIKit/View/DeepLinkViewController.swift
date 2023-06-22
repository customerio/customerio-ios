import Foundation
import UIKit

class DeepLinkViewController: BaseViewController {
    static func newInstance() -> DeepLinkViewController {
        UIStoryboard.getViewController(identifier: "DeepLinkViewController")
    }

    @IBOutlet var linkText: UILabel!
    @IBOutlet var linkTypeText: UILabel!
    var deepLinkInfo: [String: String]?
    override func viewDidLoad() {
        super.viewDidLoad()

        if let info = deepLinkInfo {
            if let type = info["linkType"] {
                linkTypeText.text = "Link Type : \(type)"
            }

            if let url = info["link"] {
                linkText.text = "Link : \(url)"
            }
        }
    }
}
