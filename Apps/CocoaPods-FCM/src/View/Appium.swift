import Foundation
import SwiftUI

extension View {
    // Centralized way to set the identifier on a View so Appium can find the view.
    func setAppiumId(_ viewId: String?) -> some View {
        accessibility(identifier: viewId ?? "")
    }
}
