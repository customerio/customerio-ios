import Foundation

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
}
