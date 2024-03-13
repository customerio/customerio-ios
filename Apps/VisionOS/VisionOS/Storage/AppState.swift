import Foundation

extension [InlineNavigationLink]: UserDefaultsCodable {
    static func storageKey() -> String {
        "navigationPath"
    }

    static func empty() -> [Element] {
        []
    }
}

extension Set<InlineNavigationLink>: UserDefaultsCodable {
    static func storageKey() -> String {
        "visitedLinks"
    }

    static func empty() -> Set<Element> {
        .init()
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

    @Published var navigationPath: [InlineNavigationLink] = .loadFromStorage() {
        didSet {
            UserDefaults.standard.setValue(
                navigationPath.toJson(),
                forKey: [InlineNavigationLink].storageKey()
            )
            visitedLinks.formUnion(navigationPath)
        }
    }

    @Published var visitedLinks: Set<InlineNavigationLink> = .loadFromStorage() {
        didSet {
            UserDefaults.standard.setValue(
                visitedLinks.toJson(),
                forKey: Set<InlineNavigationLink>.storageKey()
            )
        }
    }
}
