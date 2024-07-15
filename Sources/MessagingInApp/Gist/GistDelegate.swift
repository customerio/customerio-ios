import UIKit

public protocol GistDelegate: AnyObject {
    func messageShown(message: Message)
    func messageDismissed(message: Message)
    func messageError(message: Message)
    func action(message: Message, currentRoute: String, action: String, name: String, shouldTrackMetric: Bool)
}
