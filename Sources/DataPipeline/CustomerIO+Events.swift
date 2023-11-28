import CioInternalCommon
import Foundation

// MARK: - Typed Event Signatures

public extension CustomerIO {
    // make a note in the docs on this that we removed the old "options" property
    // and they need to write a middleware/enrichment now.
    // the objc version should accomodate them if it's really needed.

    func track<P: Codable>(name: String, properties: P?) {
        CIODataPipeline.shared().track(name: name, properties: properties)
    }

    func track(name: String) {
        CIODataPipeline.shared().track(name: name)
    }

    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - userId: A database ID for this user. If you don't have a userId
    ///     but want to record traits, just pass traits into the event and they will be associated
    ///     with the anonymousId of that user.  In the case when user logs out, make sure to
    ///     call ``reset()`` to clear the user's identity info. For more information on how we
    ///     generate the UUID and Apple's policies on IDs, see
    ///      https://segment.io/libraries/ios#ids
    /// - traits: A dictionary of traits you know about the user. Things like: email, name, plan, etc.
    func identify<T: Codable>(userId: String, traits: T?) {
        CIODataPipeline.shared().identify(userId: userId, traits: traits)
    }

    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - traits: A dictionary of traits you know about the user. Things like: email, name, plan, etc.
    func identify<T: Codable>(traits: T) {
        CIODataPipeline.shared().identify(traits: traits)
    }

    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - userId: A database ID for this user.
    ///     For more information on how we generate the UUID and Apple's policies on IDs, see
    ///     https://segment.io/libraries/ios#ids
    /// In the case when user logs out, make sure to call ``reset()`` to clear user's identity info.
    func identify(userId: String) {
        CIODataPipeline.shared().identify(userId: userId)
    }

    func screen<P: Codable>(title: String, category: String? = nil, properties: P?) {
        CIODataPipeline.shared().screen(title: title, category: category, properties: properties)
    }

    func screen(title: String, category: String? = nil) {
        CIODataPipeline.shared().screen(title: title, category: category)
    }

    func group<T: Codable>(groupId: String, traits: T?) {
        CIODataPipeline.shared().group(groupId: groupId, traits: traits)
    }

    func group(groupId: String) {
        CIODataPipeline.shared().group(groupId: groupId)
    }

    func alias(newId: String) {
        CIODataPipeline.shared().alias(newId: newId)
    }
}

// MARK: - Untyped Event Signatures

public extension CustomerIO {
    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - userId: A database ID for this user. If you don't have a userId
    ///     but want to record traits, just pass traits into the event and they will be associated
    ///     with the anonymousId of that user.  In the case when user logs out, make sure to
    ///     call ``reset()`` to clear the user's identity info. For more information on how we
    ///     generate the UUID and Apple's policies on IDs, see
    ///      https://segment.io/libraries/ios#ids
    ///   - properties: A dictionary of traits you know about the user. Things like: email, name, plan, etc.
    func track(name: String, properties: [String: Any]? = nil) {
        CIODataPipeline.shared().track(name: name, properties: properties)
    }

    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - userId: A database ID for this user. If you don't have a userId
    ///     but want to record traits, just pass traits into the event and they will be associated
    ///     with the anonymousId of that user.  In the case when user logs out, make sure to
    ///     call ``reset()`` to clear the user's identity info. For more information on how we
    ///     generate the UUID and Apple's policies on IDs, see
    ///      https://segment.io/libraries/ios#ids
    ///   - traits: A dictionary of traits you know about the user. Things like: email, name, plan, etc.
    /// In the case when user logs out, make sure to call ``reset()`` to clear user's identity info.
    func identify(userId: String, traits: [String: Any]? = nil) {
        CIODataPipeline.shared().identify(userId: userId, traits: traits)
    }

    /// Track a screen change with a title, category and other properties.
    /// - Parameters:
    ///   - screenTitle: The title of the screen being tracked.
    ///   - category: A category to the type of screen if it applies.
    ///   - properties: Any extra metadata associated with the screen. e.g. method of access, size, etc.
    func screen(title: String, category: String? = nil, properties: [String: Any]? = nil) {
        CIODataPipeline.shared().screen(title: title, category: category, properties: properties)
    }

    /// Associate a user with a group such as a company, organization, project, etc.
    /// - Parameters:
    ///   - groupId: A unique identifier for the group identification in your system.
    ///   - traits: Traits of the group you may be interested in such as email, phone or name.
    func group(groupId: String, traits: [String: Any]?) {
        CIODataPipeline.shared().group(groupId: groupId, traits: traits)
    }
}
