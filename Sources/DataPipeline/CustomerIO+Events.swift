import CioInternalCommon
import Foundation

// MARK: - Typed Event Signatures

public extension CustomerIO {
    func track(name: String) {
        DataPipeline.shared.analytics.track(name: name)
    }

    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - traits: A dictionary of traits you know about the user. Things like: email, name, plan, etc.
    @available(*, deprecated, message: "Use 'identify(userId:traits:)' with [String: Any] traits parameter instead. Support for Codable traits will be removed in a future version.")
    func identify<T: Codable>(traits: T) {
        DataPipeline.shared.analytics.identify(traits: traits)
    }

    @available(*, deprecated, message: "Use 'screen(title:properties:)' with [String: Any] properties parameter instead. Support for Codable properties will be removed in a future version.")
    func screen<P: Codable>(title: String, category: String? = nil, properties: P?) {
        DataPipeline.shared.analytics.screen(title: title, category: category, properties: properties)
    }

    func screen(title: String, category: String?) {
        DataPipeline.shared.analytics.screen(title: title, category: category)
    }

    func alias(newId: String) {
        DataPipeline.shared.analytics.alias(newId: newId)
    }
}

// MARK: - Untyped Event Signatures

public extension CustomerIO {
    /// Track a screen change with a title, category and other properties.
    /// - Parameters:
    ///   - screenTitle: The title of the screen being tracked.
    ///   - category: A category to the type of screen if it applies.
    ///   - properties: Any extra metadata associated with the screen. e.g. method of access, size, etc.
    func screen(title: String, category: String? = nil, properties: [String: Any]? = nil) {
        DataPipeline.shared.analytics.screen(title: title, category: category, properties: properties?.sanitizedForJSON())
    }
}
