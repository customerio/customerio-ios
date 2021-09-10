import Foundation

// https://customer.io/docs/api/#operation/add_device
internal struct RegisterDeviceRequest: Codable {
    let device: Device
}
