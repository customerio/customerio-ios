import Foundation
import SampleAppsCommon
import SwiftUI

class UserManager: ObservableObject {
    private let keyValueStore = KeyValueStore()

    @Published var isUserLoggedIn: Bool = false

    init() {
        self.isUserLoggedIn = keyValueStore.loggedInUserEmail != nil
    }

    func userLoggedIn(email: String) {
        keyValueStore.loggedInUserEmail = email
        isUserLoggedIn = true
    }

    func logout() {
        keyValueStore.loggedInUserEmail = nil
        isUserLoggedIn = false
    }
}
