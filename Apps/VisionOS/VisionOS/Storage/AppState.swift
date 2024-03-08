import Foundation

struct ScreenTitleConfig {
    let screenTitle: String
    let menuTitle: String
    let showVisionProLogo: Bool

    init(_ screenTitle: String, menuTitle: String? = nil, showVisionProLogo: Bool = false) {
        self.screenTitle = screenTitle
        self.menuTitle = menuTitle ?? screenTitle
        self.showVisionProLogo = showVisionProLogo
    }
}

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var profile: Profile = .loadFromStorage() {
        didSet {
            UserDefaults.standard.setValue(
                profile.toJson(),
                forKey: Profile.storageKey()
            )
        }
    }

    @Published var workspaceSettings: WorkspaceSettings = .loadFromStorage() {
        didSet {
            UserDefaults.standard.setValue(
                workspaceSettings.toJson(),
                forKey: WorkspaceSettings.storageKey()
            )
        }
    }

    // MARK: non persistent state

    @Published var titleConfig: ScreenTitleConfig = .init("")
    @Published var errorMessage: String = ""
    @Published var successMessage: String = ""
}
