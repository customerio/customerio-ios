import CioDataPipelines
import UIKit
import UserNotifications

class InternalSettingsViewController: BaseViewController {
    static func newInstance() -> InternalSettingsViewController {
        UIStoryboard.getViewController(identifier: "InternalSettingsViewController")
    }

    var settingsViewModel: SettingsViewModel!
    private let screenName = "internal-settings"

    // MARK: - Outlets

    @IBOutlet var workspaceNameLabel: UILabel!

    @IBOutlet var apiHostTextField: ThemeTextField!
    @IBOutlet var cdnHostTextField: ThemeTextField!

    @IBOutlet var testModeYesButton: UIButton!
    @IBOutlet var testModeNoButton: UIButton!

    @IBOutlet var screenNameLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        assert(settingsViewModel != nil, "ViewModel must be set before using InternalSetttingsViewController")

        title = "Internal settings"
        screenNameLabel.text = screenName

        configureButtonActions()
        setInitialValues()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false

        CustomerIO.shared.screen(title: screenName, properties: [:])
    }

    func setInitialValues() {
        workspaceNameLabel.text = BuildEnvironment.CustomerIO.workspaceName

        cdnHostTextField.text = settingsViewModel.settings.internalSettings.cdnHost
        apiHostTextField.text = settingsViewModel.settings.internalSettings.apiHost

        // test mode
        testModeYesButton.isSelected = settingsViewModel.settings.internalSettings.testMode
        testModeNoButton.isSelected = !settingsViewModel.settings.internalSettings.testMode
    }

    func configureButtonActions() {
        // testMode
        testModeYesButton.addAction(UIAction(handler: { [weak self] _ in
            self?.setTestMode(true)
        }), for: .touchUpInside)
        testModeNoButton.addAction(UIAction(handler: { [weak self] _ in
            self?.setTestMode(false)
        }), for: .touchUpInside)
    }

    func setTestMode(_ testMode: Bool) {
        settingsViewModel.testModeUpdated(testMode)
        setInitialValues()
    }

    // MARK: - Actions

    @IBAction func cdnHostChanged(_ sender: UITextField) {
        settingsViewModel.cdnHostUpdated(cdnHostTextField.text ?? "")
    }

    @IBAction func apiHostChanged(_ sender: UITextField) {
        settingsViewModel.apiHostUpdated(cdnHostTextField.text ?? "")
    }
}
