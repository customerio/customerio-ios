import Common
import Foundation
import Gist

// wrapper around Gist SDK to make it mockable
internal protocol InAppProvider: AutoMockable {
    func initialize(id: String, delegate: GistDelegate)
    func setProfileIdentifier(_ id: String)
    func clearIdentify()
}

// sourcery: InjectRegister = "InAppProvider"
internal class GistInAppProvider: InAppProvider {
    func initialize(id: String, delegate: GistDelegate) {
        Gist.shared.setup(organizationId: id)
        Gist.shared.delegate = delegate
    }

    func setProfileIdentifier(_ id: String) {
        Gist.shared.setUserToken(id)
    }

    func clearIdentify() {
        Gist.shared.clearUserToken()
    }
}
