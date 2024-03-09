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

class ViewModel: ObservableObject {
    @Published var titleConfig: ScreenTitleConfig = .init("")
    @Published var errorMessage: String = ""
    @Published var successMessage: String = ""
}
