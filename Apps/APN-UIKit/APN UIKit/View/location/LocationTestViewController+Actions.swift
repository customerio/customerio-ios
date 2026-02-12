import UIKit

// MARK: - Click Handlers

extension LocationTestViewController {
    @objc func presetButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index >= 0, index < presetLocations.count else { return }

        let preset = presetLocations[index]
        setLocation(latitude: preset.latitude, longitude: preset.longitude, sourceName: preset.name)
    }

    @objc func useCurrentLocationTapped() {
        requestCurrentLocation()
    }

    @objc func setManualLocationTapped() {
        setManualLocation()
    }

    @objc func toggleMinusSign(_ sender: UIBarButtonItem) {
        guard let textField = [latitudeTextField, longitudeTextField].first(where: { $0.isFirstResponder }) else {
            return
        }

        if let text = textField.text, text.hasPrefix("-") {
            textField.text = String(text.dropFirst())
        } else {
            textField.text = "-" + (textField.text ?? "")
        }
    }

    @objc func doneButtonTapped() {
        view.endEditing(true)
    }
}
