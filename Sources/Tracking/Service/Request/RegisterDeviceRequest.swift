import Foundation

// https://customer.io/docs/api/#operation/add_device
internal struct RegisterDeviceRequest<T: Encodable>: Encodable {
    let device: Device<T>
}
