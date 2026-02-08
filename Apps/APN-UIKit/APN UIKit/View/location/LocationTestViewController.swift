import CioDataPipelines
import CioLocation
import CoreLocation
import UIKit

struct PresetLocation {
    let name: String
    let latitude: Double
    let longitude: Double
}

/// View controller for testing the Location module with preset, device, or manual location options.
class LocationTestViewController: BaseViewController {
    static func newInstance() -> LocationTestViewController {
        UIStoryboard.getViewController(identifier: "LocationTestViewController")
    }

    // MARK: - Properties

    let locationManager = CLLocationManager()
    var scrollView: UIScrollView!
    var lastSetLocationLabel: UILabel!
    var latitudeTextField: ThemeTextField!
    var longitudeTextField: ThemeTextField!
    var setManualLocationButton: ThemeButton!
    var useCurrentLocationButton: ThemeButton!

    /// Tracks if we're in the "user tapped Use Current Location and we're waiting for permission" flow.
    /// Used to avoid auto-starting a location fetch when the screen opens and auth is already granted.
    var userRequestedCurrentLocation = false

    let presetLocations: [PresetLocation] = [
        PresetLocation(name: "New York", latitude: 40.7128, longitude: -74.0060),
        PresetLocation(name: "London", latitude: 51.5074, longitude: -0.1278),
        PresetLocation(name: "Tokyo", latitude: 35.6762, longitude: 139.6503),
        PresetLocation(name: "Sydney", latitude: -33.8688, longitude: 151.2093),
        PresetLocation(name: "São Paulo", latitude: -23.5505, longitude: -46.6333),
        PresetLocation(name: "0, 0", latitude: 0.0, longitude: 0.0)
    ]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupLocationManager()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
        CustomerIO.shared.screen(title: "Location Test")
        // Start with empty manual entry fields so they are not pre-populated from a previous device fetch
        latitudeTextField?.text = ""
        longitudeTextField?.text = ""
        addKeyboardObservers()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardObservers()
    }

    // MARK: - UI Setup

    private func setupUI() {
        title = "Location Test"
        view.backgroundColor = .white

        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        // Option 1: Quick Presets
        stackView.addArrangedSubview(createOptionSection(
            title: "OPTION 1: QUICK PRESETS",
            description: "Tap a city to set its coordinates",
            content: createPresetsGrid()
        ))

        // OR separator
        stackView.addArrangedSubview(createOrSeparator())

        // Option 2: Device Location
        stackView.addArrangedSubview(createOptionSection(
            title: "OPTION 2: DEVICE LOCATION",
            description: "Fetches coordinates from device (GPS, Wi‑Fi, or cell). Label shows source when known (e.g. Simulated).",
            content: createDeviceLocationButton()
        ))

        // OR separator
        stackView.addArrangedSubview(createOrSeparator())

        // Option 3: Manual Entry
        stackView.addArrangedSubview(createOptionSection(
            title: "OPTION 3: MANUAL ENTRY",
            description: "Enter custom coordinates",
            content: createManualEntrySection()
        ))

        // Status section
        stackView.addArrangedSubview(createStatusSection())
    }
}
