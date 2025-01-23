import UIKit

class InlineInAppMessageUikitViewController: BaseViewController {
    static func newInstance() -> InlineInAppMessageUikitViewController {
        UIStoryboard.getViewController(identifier: "InlineInAppMessageUikitViewController")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
    }
}
