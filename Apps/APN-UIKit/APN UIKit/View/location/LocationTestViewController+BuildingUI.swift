import UIKit

// MARK: - Building UI

extension LocationTestViewController {
    func createOptionSection(title: String, description: String, content: UIView) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(white: 0.97, alpha: 1.0)
        container.layer.cornerRadius = 10
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor(white: 0.9, alpha: 1.0).cgColor

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.textColor = .darkGray
        stackView.addArrangedSubview(titleLabel)

        stackView.addArrangedSubview(content)

        let descriptionLabel = UILabel()
        descriptionLabel.text = description
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .gray
        stackView.addArrangedSubview(descriptionLabel)

        return container
    }

    func createPresetsGrid() -> UIView {
        let gridStack = UIStackView()
        gridStack.axis = .vertical
        gridStack.spacing = 8

        var currentRowStack: UIStackView?
        for (index, preset) in presetLocations.enumerated() {
            if index % 3 == 0 {
                let rowStack = UIStackView()
                rowStack.axis = .horizontal
                rowStack.spacing = 8
                rowStack.distribution = .fillEqually
                gridStack.addArrangedSubview(rowStack)
                currentRowStack = rowStack
            }
            let button = createPresetButton(name: preset.name, index: index)
            currentRowStack?.addArrangedSubview(button)
        }

        return gridStack
    }

    func createPresetButton(name: String, index: Int) -> UIButton {
        let button = ThemeButton()
        button.setTitle(name, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14)
        button.tag = index
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.addTarget(self, action: #selector(presetButtonTapped(_:)), for: .touchUpInside)

        return button
    }

    func createDeviceLocationButton() -> UIView {
        useCurrentLocationButton = ThemeButton()
        useCurrentLocationButton.setTitle("📍  Use Current Location", for: .normal)
        useCurrentLocationButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        useCurrentLocationButton.addTarget(self, action: #selector(useCurrentLocationTapped), for: .touchUpInside)

        return useCurrentLocationButton
    }

    func createManualEntrySection() -> UIView {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12

        let latLabel = UILabel()
        latLabel.text = "Latitude"
        latLabel.font = .systemFont(ofSize: 14)
        stackView.addArrangedSubview(latLabel)

        latitudeTextField = ThemeTextField()
        latitudeTextField.placeholder = "e.g., 40.7128"
        latitudeTextField.keyboardType = .decimalPad
        latitudeTextField.delegate = self
        latitudeTextField.heightAnchor.constraint(equalToConstant: 40).isActive = true
        addMinusButtonToTextField(latitudeTextField)
        stackView.addArrangedSubview(latitudeTextField)

        let lonLabel = UILabel()
        lonLabel.text = "Longitude"
        lonLabel.font = .systemFont(ofSize: 14)
        stackView.addArrangedSubview(lonLabel)

        longitudeTextField = ThemeTextField()
        longitudeTextField.placeholder = "e.g., -74.0060"
        longitudeTextField.keyboardType = .decimalPad
        longitudeTextField.delegate = self
        longitudeTextField.heightAnchor.constraint(equalToConstant: 40).isActive = true
        addMinusButtonToTextField(longitudeTextField)
        stackView.addArrangedSubview(longitudeTextField)

        setManualLocationButton = ThemeButton()
        setManualLocationButton.setTitle("Set Location", for: .normal)
        setManualLocationButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        setManualLocationButton.addTarget(self, action: #selector(setManualLocationTapped), for: .touchUpInside)
        stackView.addArrangedSubview(setManualLocationButton)

        return stackView
    }

    func addMinusButtonToTextField(_ textField: UITextField) {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()

        let minusButton = UIBarButtonItem(title: "+/−", style: .plain, target: self, action: #selector(toggleMinusSign(_:)))
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonTapped))

        toolbar.items = [minusButton, flexSpace, doneButton]
        textField.inputAccessoryView = toolbar
    }

    func createOrSeparator() -> UIView {
        let container = UIView()
        container.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let leftLine = UIView()
        leftLine.backgroundColor = UIColor(white: 0.85, alpha: 1.0)
        leftLine.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(leftLine)

        let orLabel = UILabel()
        orLabel.text = "OR"
        orLabel.font = .boldSystemFont(ofSize: 12)
        orLabel.textColor = .gray
        orLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(orLabel)

        let rightLine = UIView()
        rightLine.backgroundColor = UIColor(white: 0.85, alpha: 1.0)
        rightLine.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rightLine)

        NSLayoutConstraint.activate([
            leftLine.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leftLine.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            leftLine.heightAnchor.constraint(equalToConstant: 1),
            leftLine.trailingAnchor.constraint(equalTo: orLabel.leadingAnchor, constant: -12),

            orLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            orLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            rightLine.leadingAnchor.constraint(equalTo: orLabel.trailingAnchor, constant: 12),
            rightLine.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            rightLine.heightAnchor.constraint(equalToConstant: 1),
            rightLine.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        return container
    }

    func createStatusSection() -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        container.layer.cornerRadius = 8

        lastSetLocationLabel = UILabel()
        lastSetLocationLabel.text = "No location set yet"
        lastSetLocationLabel.font = .systemFont(ofSize: 14)
        lastSetLocationLabel.textColor = .darkGray
        lastSetLocationLabel.numberOfLines = 0
        lastSetLocationLabel.textAlignment = .center
        lastSetLocationLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lastSetLocationLabel)

        NSLayoutConstraint.activate([
            lastSetLocationLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            lastSetLocationLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            lastSetLocationLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            lastSetLocationLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        return container
    }
}
