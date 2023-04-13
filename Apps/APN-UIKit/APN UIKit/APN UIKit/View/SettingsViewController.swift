import UIKit

class SettingsViewController: UIViewController {

    static func newInstance() -> SettingsViewController {
        UIStoryboard.getViewController(identifier: "SettingsViewController")
    }
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
         super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = false
    }
    
    // MARK: - Actions
    
    @IBAction func saveSettings(_ sender: UIButton) {
        showAlert(withMessage: "Saving settings will require an app restart to bring the changes in effect.")
    }
}
