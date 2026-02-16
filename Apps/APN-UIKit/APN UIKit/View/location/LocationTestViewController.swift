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
    var requestSdkLocationOnceButton: ThemeButton!
    var stopLocationUpdatesButton: ThemeButton!

    /// Tracks if we're in the "user tapped Use Current Location and we're waiting for permission" flow.
    /// Used to avoid auto-starting a location fetch when the screen opens and auth is already granted.
    var userRequestedCurrentLocation = false

    /// Tracks if we're in the "user tapped Request location once (SDK) and we're waiting for permission" flow.
    var userRequestedSdkLocationUpdate = false

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
        // Start with empty manual entry fields once when the screen loads
        latitudeTextField?.text = ""
        longitudeTextField?.text = ""
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
        CustomerIO.shared.screen(title: "Location Test")
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

        let (scroll, contentView) = setupScrollViewAndContent()
        scrollView = scroll

        let stackView = setupStackView(in: contentView)
        addOptionSections(to: stackView)
    }

    private func setupScrollViewAndContent() -> (UIScrollView, UIView) {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(contentView)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scroll.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])
        return (scroll, contentView)
    }

    private func setupStackView(in contentView: UIView) -> UIStackView {
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
        return stackView
    }

    private func addOptionSections(to stackView: UIStackView) {
        stackView.addArrangedSubview(createOptionSection(
            title: "OPTION 1: QUICK PRESETS",
            description: "Tap a city to set its coordinates",
            content: createPresetsGrid()
        ))
        stackView.addArrangedSubview(createOrSeparator())

        stackView.addArrangedSubview(createOptionSection(
            title: "OPTION 2: SDK LOCATION",
            description: "Ask for permission if needed, then SDK fetches location once. Use \"Stop updates\" to cancel.",
            content: createSdkLocationButtons()
        ))
        stackView.addArrangedSubview(createOrSeparator())

        stackView.addArrangedSubview(createOptionSection(
            title: "OPTION 3: MANUALLY SET FROM DEVICE",
            description: "Fetches coordinates from device (GPS, Wi‑Fi, or cell) and sends them to the SDK via setLastKnownLocation. Label shows source when known (e.g. Simulated).",
            content: createDeviceLocationButton()
        ))
        stackView.addArrangedSubview(createOrSeparator())

        stackView.addArrangedSubview(createOptionSection(
            title: "OPTION 4: MANUAL ENTRY",
            description: "Enter custom coordinates",
            content: createManualEntrySection()
        ))
        stackView.addArrangedSubview(createStatusSection())
    }
}
