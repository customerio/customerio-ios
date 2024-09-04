import CioInternalCommon
import Foundation

class RouteManager {
    private static var currentRoute = ""

    static func getCurrentRoute() -> String {
        currentRoute
    }

    static func setCurrentRoute(_ currentRoute: String) {
        self.currentRoute = currentRoute
        DIGraphShared.shared.logger.info("Route changed to: \(currentRoute)")
    }

    static func clearCurrentRoute() {
        currentRoute = ""
        DIGraphShared.shared.logger.info("Route cleared")
    }
}
