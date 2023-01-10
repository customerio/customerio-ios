import Foundation
import Common

public protocol CustomerIOInstance: AutoMockable {
    var siteId: String? { get }

    func identify(
        identifier: String,
        body: [String: Any]
    )

    // sourcery:Name=identifyEncodable
    // sourcery:DuplicateMethod=identify
    func identify<RequestBody: Encodable>(
        identifier: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(body)"
        body: RequestBody
    )

    func clearIdentify()

    func track(
        name: String,
        data: [String: Any]
    )

    // sourcery:Name=trackEncodable
    // sourcery:DuplicateMethod=track
    func track<RequestBody: Encodable>(
        name: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        data: RequestBody?
    )

    func screen(
        name: String,
        data: [String: Any]
    )

    // sourcery:Name=screenEncodable
    // sourcery:DuplicateMethod=screen
    func screen<RequestBody: Encodable>(
        name: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        data: RequestBody?
    )

    var profileAttributes: [String: Any] { get set }
    var deviceAttributes: [String: Any] { get set }

    func registerDeviceToken(_ deviceToken: String)

    func deleteDeviceToken()

    func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    )
}
