import Foundation

// ScreenViewData wraps an encoder to allow returning of custom data for automatic screenview tracking
struct ScreenViewData: Encodable {
    let data: Encodable
    
    func encode(to encoder: Encoder) throws {
        try data.encode(to: encoder)
    }
}

// ScreenViewDefaultData is the standard data supplied along with an automatic screenview
internal struct ScreenViewDefaultData: Codable {}
