import UIKit

class SettingsViewController: UIViewController {
    static func newInstance() -> SettingsViewController {
        UIStoryboard.getViewController(identifier: "SettingsViewController")
    }
    
    // MARK: - Outlets
    @IBOutlet weak var deviceTokenTextField: ThemeTextField!
    @IBOutlet weak var apiKeyTextField: ThemeTextField!
    @IBOutlet weak var siteIdTextField: ThemeTextField!
    @IBOutlet weak var trackUrlTextField: ThemeTextField!
    @IBOutlet weak var trackDeviceToggle: UISwitch!
    @IBOutlet weak var debugModeToggle: UISwitch!
    @IBOutlet weak var trackScreenToggle: UISwitch!
    @IBOutlet weak var enablePushToggle: UISwitch!
    @IBOutlet weak var bgQMinTasks: ThemeTextField!
    @IBOutlet weak var bgQTakDelayTextField: ThemeTextField!
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
