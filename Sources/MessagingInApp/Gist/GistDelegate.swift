import UIKit

public protocol GistDelegate: AnyObject {
    func messageShown(message: Message)
    func inlineMessageLoaded(message: Message, gistView: GistView)
    func messageDismissed(message: Message)
    func messageError(message: Message)
    func action(message: Message, currentRoute: String, action: String, name: String)
}
