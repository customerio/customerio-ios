import CioInternalCommon
import Foundation
import UIKit

// sourcery: InjectRegisterShared = "Gist"
// sourcery: InjectSingleton
public class Gist {
    private let gistDelegate: GistDelegate
    private let inAppMessageManager: InAppMessageManager
    private let messageQueueManager: MessageQueueManager

    init(
        gistDelegate: GistDelegate,
        inAppMessageManager: InAppMessageManager,
        messageQueueManager: MessageQueueManager
    ) {
        self.gistDelegate = gistDelegate
        self.inAppMessageManager = inAppMessageManager
        self.messageQueueManager = messageQueueManager
    }

    public func resetState() {
        inAppMessageManager.dispatch(action: .resetState)
    }

    func setEventListener(_ eventListener: InAppEventListener?) {
        gistDelegate.setEventListener(eventListener)
    }

    public func setUserToken(_ userToken: String) {
        inAppMessageManager.fetchState { [self] state in
            if state.userId == userToken {
                return
            }

            inAppMessageManager.dispatch(action: .setUserIdentifier(user: userToken))
            messageQueueManager.setupPollingAndFetch(skipMessageFetch: false, pollingInterval: state.pollInterval)
        }
    }

    public func setCurrentRoute(_ currentRoute: String) {
        inAppMessageManager.fetchState { [self] state in
            if state.currentRoute == currentRoute {
                return // ignore request, route has not changed.
            }

            inAppMessageManager.dispatch(action: .setPageRoute(route: currentRoute))
        }
    }

    public func dismissMessage() {
        inAppMessageManager.fetchState { [self] state in
            guard case .displayed(let message) = state.currentMessageState else {
                return
            }

            inAppMessageManager.dispatch(action: .dismissMessage(message: message))
        }
    }
}
