@testable import CioTracking
import Foundation

/// Example event body
public struct ScreenViewData: Codable, Equatable {
    var variant: Int?
    var darkMode: Bool?
}

public extension ScreenViewData {
    static func random() -> ScreenViewData {
        ScreenViewData(variant: Int.random(in: 1 ... 5),
                       darkMode: Bool.random())
    }

    static func blank() -> ScreenViewData {
        ScreenViewData(variant: nil, darkMode: nil)
    }
}
