@testable import CioTracking
import Foundation

/// Example screen view body
public struct ExampleScreenViewData: Codable, Equatable {
    var variant: Int?
    var darkMode: Bool?
}

public extension ExampleScreenViewData {
    static func random() -> ExampleScreenViewData {
        ExampleScreenViewData(
            variant: Int.random(in: 1 ... 5),
            darkMode: Bool.random()
        )
    }

    static func blank() -> ExampleScreenViewData {
        ExampleScreenViewData(variant: nil, darkMode: nil)
    }
}
