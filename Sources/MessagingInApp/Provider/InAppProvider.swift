import Common
import Foundation
import Gist

// wrapper around Gist SDK to make it mockable
internal protocol InAppProvider: AutoMockable {
    func initialize(organizationId: String, delegate: GistDelegate)
    func setProfileIdentifier(_ id: String)
    func clearIdentify()
    func setRoute(_ route: String)
}

// sourcery: InjectRegister = "InAppProvider"
internal class GistInAppProvider: InAppProvider {
    func initialize(organizationId: String, delegate: GistDelegate) {
        Gist.shared.setup(organizationId: organizationId)
        Gist.shared.delegate = delegate
    }

    func setProfileIdentifier(_ id: String) {
        Gist.shared.setUserToken(id)
    }

    func clearIdentify() {
        Gist.shared.clearUserToken()
    }

    func setRoute(_ route: String) {
        Gist.shared.setCurrentRoute(route)
    }
}
