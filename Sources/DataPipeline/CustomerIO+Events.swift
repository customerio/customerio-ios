import CioInternalCommon
import Foundation

// MARK: - Typed Event Signatures

// TODO: Add APITest for it?
public extension CustomerIO {
    func track<P: Codable>(name: String, properties: P?) {
        DataPipeline.shared.analytics.track(name: name, properties: properties)
    }

    func track(name: String) {
        DataPipeline.shared.analytics.track(name: name)
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
        guard let traits = traits else {
            DataPipeline.shared.identify(identifier: userId, body: EmptyRequestBody())
            return
        }
        DataPipeline.shared.identify(identifier: userId, body: traits)
    }

    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - traits: A dictionary of traits you know about the user. Things like: email, name, plan, etc.
    func identify<T: Codable>(traits: T) {
        DataPipeline.shared.analytics.identify(traits: traits)
    }

    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - userId: A database ID for this user.
    ///     For more information on how we generate the UUID and Apple's policies on IDs, see
    ///     https://segment.io/libraries/ios#ids
    /// In the case when user logs out, make sure to call ``reset()`` to clear user's identity info.
    func identify(userId: String) {
        DataPipeline.shared.identify(identifier: userId, body: [:])
    }

    func screen<P: Codable>(title: String, category: String? = nil, properties: P?) {
        DataPipeline.shared.analytics.screen(title: title, category: category, properties: properties)
    }

    func screen(title: String, category: String? = nil) {
        DataPipeline.shared.analytics.screen(title: title, category: category)
    }

    func group<T: Codable>(groupId: String, traits: T?) {
        DataPipeline.shared.analytics.group(groupId: groupId, traits: traits)
    }

    func group(groupId: String) {
        DataPipeline.shared.analytics.group(groupId: groupId)
    }

    func alias(newId: String) {
        DataPipeline.shared.analytics.alias(newId: newId)
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
        DataPipeline.shared.analytics.track(name: name, properties: properties)
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
        DataPipeline.shared.identify(identifier: userId, body: traits ?? [:])
    }

    /// Track a screen change with a title, category and other properties.
    /// - Parameters:
    ///   - screenTitle: The title of the screen being tracked.
    ///   - category: A category to the type of screen if it applies.
    ///   - properties: Any extra metadata associated with the screen. e.g. method of access, size, etc.
    func screen(title: String, category: String? = nil, properties: [String: Any]? = nil) {
        DataPipeline.shared.analytics.screen(title: title, category: category, properties: properties)
    }

    /// Associate a user with a group such as a company, organization, project, etc.
    /// - Parameters:
    ///   - groupId: A unique identifier for the group identification in your system.
    ///   - traits: Traits of the group you may be interested in such as email, phone or name.
    func group(groupId: String, traits: [String: Any]?) {
        DataPipeline.shared.analytics.group(groupId: groupId, traits: traits)
    }
}
