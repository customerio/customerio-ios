import CioInternalCommon
import UIKit

// MARK: - Location Section

extension MainSettingsViewController {
    func setupLocationSection() {
        let topSpacer = UIView()
        topSpacer.heightAnchor.constraint(equalToConstant: 16).isActive = true
        settingsStackView.addArrangedSubview(topSpacer)

        let sectionStack = UIStackView()
        sectionStack.axis = .vertical
        sectionStack.spacing = 8

        let headerLabel = UILabel()
        headerLabel.text = "CioLocation"
        headerLabel.font = UIFont(name: "Avenir-Black", size: 18) ?? .boldSystemFont(ofSize: 18)
        headerLabel.textColor = UIColor(white: 0.243, alpha: 1.0)
        sectionStack.addArrangedSubview(headerLabel)

        let modeLabel = UILabel()
        modeLabel.text = "trackingMode"
        modeLabel.font = .systemFont(ofSize: 15)
        modeLabel.textColor = UIColor(white: 0.243, alpha: 1.0)
        sectionStack.addArrangedSubview(modeLabel)

        let buttonRow = UIStackView()
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually

        locationTrackingModeButtons = LocationTrackingModeSetting.allCases.map { mode in
            let button = ThemeButton()
            button.setTitle(mode.displayName, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13)
            button.tag = LocationTrackingModeSetting.allCases.firstIndex(of: mode) ?? 0
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            button.addTarget(self, action: #selector(locationTrackingModeButtonTapped(_:)), for: .touchUpInside)
            buttonRow.addArrangedSubview(button)
            return button
        }
        sectionStack.addArrangedSubview(buttonRow)

        settingsStackView.addArrangedSubview(sectionStack)
    }

    func setLocationInitialValues() {
        let active = settingsViewModel.settings.location?.trackingMode ?? .onAppStart
        for button in locationTrackingModeButtons {
            let mode = LocationTrackingModeSetting.allCases[button.tag]
            button.isSelected = mode == active
            button.alpha = mode == active ? 1.0 : 0.5
        }
    }

    @objc func locationTrackingModeButtonTapped(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < LocationTrackingModeSetting.allCases.count else { return }
        let selected = LocationTrackingModeSetting.allCases[sender.tag]
        settingsViewModel.locationTrackingModeUpdated(selected)
        setLocationInitialValues()
    }
}
