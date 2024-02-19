import Foundation

public extension CustomerIOInstance {
    @available(*, unavailable, message: "CioTracking module is no longer supported. Use 'identify(userId:traits:)' from 'CioDataPipelines' for improved features. See documentation for migration details.")
    func identify(identifier: String) {}

    @available(*, unavailable, message: "CioTracking module is no longer supported. Use 'identify(userId:traits:)' from 'CioDataPipelines' for improved features. See documentation for migration details.")
    func identify(userId: String, body: [String: Any]) {}

    @available(*, unavailable, message: "CioTracking module is no longer supported. Use 'identify(userId:traits:)' from 'CioDataPipelines' for improved features. See documentation for migration details.")
    func identify<RequestBody: Codable>(identifier: String, body: RequestBody) {}

    @available(*, unavailable, message: "CioTracking module is no longer supported. Use 'identify(userId:traits:)' from 'CioDataPipelines' for improved features. See documentation for migration details.")
    func identify(body: Codable) {}

    @available(*, unavailable, message: "CioTracking module is no longer supported. Use 'clearIdentify' from 'CioDataPipelines' for improved features. See documentation for migration details.")
    func clearIdentify() {}

    @available(*, unavailable, message: "CioTracking module is no longer supported. Use 'track(name:properties:)' from 'CioDataPipelines' for improved features. See documentation for migration details.")
    func track(name: String) {}

    @available(*, unavailable, message: "CioTracking module is no longer supported. Use 'track(name:properties:)' from 'CioDataPipelines' for improved features. See documentation for migration details.")
    func track(name: String, data: [String: Any]) {}

    @available(*, unavailable, message: "CioTracking module is no longer supported. Use 'track(name:properties:)' from 'CioDataPipelines' for improved features. See documentation for migration details.")
    func track<RequestBody: Codable>(name: String, data: RequestBody?) {}

    @available(*, unavailable, message: "CioTracking module is no longer supported. Use 'screen(title:)' from 'CioDataPipelines' for improved features. See documentation for migration details.")
    func screen(name: String) {}

    @available(*, unavailable, message: "CioTracking module is no longer supported. Use 'screen(title:properties:)' from 'CioDataPipelines' for improved features. See documentation for migration details.")
    func screen(name: String, data: [String: Any]) {}

    @available(*, unavailable, message: "CioTracking module is no longer supported. Use 'screen(title:properties:)' from 'CioDataPipelines' for improved features. See documentation for migration details.")
    func screen<RequestBody: Codable>(name: String, data: RequestBody?) {}
}
