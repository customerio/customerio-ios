import Foundation
import UIKit

typealias EngineEventProperties = [String: AnyObject]

enum EngineEvent: String {
    case bootstrapped
    case routeLoaded
    case routeError
    case routeChanged
    case sizeChanged
    case tap
    case error
}

struct TapProperties {
    let name: String
    let action: String
    let system: Bool
}

enum EngineEventHandler {
    static func getTapProperties(properties: EngineEventProperties) -> TapProperties? {
        guard let parameters = properties["parameters"],
              let name = parameters["name"] as? String,
              let action = parameters["action"] as? String,
              let system = parameters["system"] as? Bool
        else {
            return nil
        }
        return TapProperties(name: name, action: action, system: system)
    }

    static func getSizeProperties(properties: EngineEventProperties) -> CGSize? {
        guard let parameters = properties["parameters"],
              let width = parameters["width"] as? CGFloat,
              let height = parameters["height"] as? CGFloat
        else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    static func getRouteChangedProperties(properties: EngineEventProperties) -> String? {
        extractRoute(properties: properties)
    }

    static func getRouteErrorProperties(properties: EngineEventProperties) -> String? {
        extractRoute(properties: properties)
    }

    /// Pulls the renderer's own description of a failure out of an `error` event.
    ///
    /// The renderer sends `{ target, errorMessage }` — e.g. `Unable to find "step-2" in payload.`
    /// That string is the only first-hand account of why a message would not render, and it was
    /// being dropped on the floor.
    static func getErrorProperties(properties: EngineEventProperties) -> String? {
        guard let parameters = properties["parameters"] else { return nil }

        let errorMessage = parameters["errorMessage"] as? String
        let target = parameters["target"] as? String

        switch (errorMessage, target) {
        case (.some(let message), .some(let target)):
            return "\(message) (target: \(target))"
        case (.some(let message), .none):
            return message
        case (.none, .some(let target)):
            return "Engine reported an error for target: \(target)"
        case (.none, .none):
            return nil
        }
    }

    static func getRouteLoadedProperties(properties: EngineEventProperties) -> String? {
        extractRoute(properties: properties)
    }

    private static func extractRoute(properties: EngineEventProperties) -> String? {
        guard let parameters = properties["parameters"],
              let route = parameters["route"] as? String
        else {
            return nil
        }
        return route
    }
}
