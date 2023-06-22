import UIKit

// Use this Base controller class to implement shared functionality
// across all controllers in the project
class BaseViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        dismissKeyboardOnTap()
    }
}
