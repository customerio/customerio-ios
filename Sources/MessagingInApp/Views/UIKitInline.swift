import CioInternalCommon
import Foundation
import UIKit

// To handle inline custom button actions.
public protocol InAppMessageViewActionDelegate: AnyObject, AutoMockable {
    // This method is called when a custom button is tapped in an inline message.
    func onActionClick(message: InAppMessage, actionValue: String, actionName: String)
}

/**
 View that can be added to a customer's app UI to display inline in-app messages.

 Usage:
 1. Create an instance of this View and add it to the customer's app UI.
 ```
 // you can construct an instance with code:
 let inAppMessageView = InAppMessageView(elementId: "elementId")
 view.addSubView(inAppMessageView)

 // Or, if you use Storyboards:
 @IBOutlet weak var inAppMessageView: InAppMessageView!
 inAppMessageView.elementId = "elementId"
 ```
 2. Position and set size of the View in app's UI. The View will adjust it's height automatically, but all other constraints are the responsibilty of app developer. You can set a height constraint if you want autolayout warnings to go away but know that the View will ignore this set height.
 */
public class InAppMessageView: UIView, GistInlineInAppMessageViewDelegate {
    // Can set in the constructor or can set later (like if you use Storyboards)
    public var elementId: String? {
        didSet {
            setupView()
        }
    }

    // Delegate to handle custom action button tap.
    public weak var onActionDelegate: InAppMessageViewActionDelegate?

    // When a fetch request is performed, it's an async operation to have the inline View notified about this fetch and the inline View processing the fetch.
    // There is currently no easy way to know when the inline View has finished processing the fetch.
    // This listener is a hack for our automated tests to know when the inline View has finished processing the fetch.
    //
    // See linear ticket MBL-427 to learn more about this limitation in our tests.
    var refreshViewListener: (() -> Void)?

    var runningHeightChangeAnimation: UIViewPropertyAnimator?
    var runningCrossFadeAnimation: UIViewPropertyAnimator?

    var messageRenderingLoadingView: UIView? {
        subviews.first { $0 is UIActivityIndicatorView }
    }

    var inAppMessageView: UIView? {
        subviews.first { $0 is GistInlineInAppMessageView }
    }

    public init(elementId: String) {
        super.init(frame: .zero)
        self.elementId = elementId

        // Setup the View and display a message, if one available. Since an elementId has been set.
        setupView()
    }

    // This is called when the View is created from a Storyboard.
    required init?(coder: NSCoder) {
        super.init(coder: coder)

        setupView()
        // An element id will not be set yet. No need to check for messages to display.
    }

    private func setupView() {
        guard let elementId, inAppMessageView == nil else {
            return // We are already setup. No need to do again.
        }

        let inlineInAppMessageView = GistInlineInAppMessageView(elementId: elementId)
        inlineInAppMessageView.delegate = self
        addSubview(inlineInAppMessageView)

        inlineInAppMessageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inlineInAppMessageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            inlineInAppMessageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            inlineInAppMessageView.widthAnchor.constraint(equalTo: widthAnchor),
            inlineInAppMessageView.heightAnchor.constraint(equalTo: heightAnchor)
        ])

        // It's important to have only 1 active constraint for height or UIKit will ignore some constraints.
        // Try to re-use a constraint if one is already added instead of replacing it. Some scenarios such as
        // when UIView is nested in a UIStackView and distribution is .fillProportionally, the height constraint StackView adds is important to keep.

        if heightConstraint == nil {
            // Customer did not set a height constraint. Create one so the View has one.
            let heightConstraint = heightAnchor.constraint(equalToConstant: 0)
            heightConstraint.priority = .required // in case a customer sets a height constraint, by us setting the highest priority, we try to have this constraint be used.
            heightConstraint.isActive = true // set isActive as the last step.
        }

        heightConstraint?.constant = 0 // start at height 0 so the View does not show.
        getRootSuperview()?.layoutIfNeeded() // Since we modified constraint, perform a UI refresh to apply the change.
    }

    public func onMessageRendered(width: CGFloat, height: CGFloat) {
        // animate height change
        guard let inAppMessageView = inAppMessageView else {
            return
        }

        inAppMessageView.isHidden = false
        animateHeight(to: height)

        if let messageRenderingLoadingView = messageRenderingLoadingView {
            animateFadeInOutInlineView(fromView: messageRenderingLoadingView, toView: inAppMessageView) {
                messageRenderingLoadingView.removeFromSuperview()
            }
        }
    }

    public func onNoMessageToDisplay() {
        animateHeight(to: 0)
    }

    public func onInlineButtonAction(message: Message, currentRoute: String, action: String, name: String) -> Bool {
        // If delegate is not set then call the global `messageActionTaken` method
        guard let onActionDelegate = onActionDelegate else {
            return false
        }
        onActionDelegate.onActionClick(message: InAppMessage(gistMessage: message), actionValue: action, actionName: name)
        return true
    }

    public func willChangeMessage(newTemplateId: String, onComplete: @escaping () -> Void) {
        // animate in loading view
        showLoadingView {
            onComplete()
        }
    }

    // Call when you want to show the loading View, indicating to the app user that a new message is being loaded.
    private func showLoadingView(onComplete: @escaping () -> Void) {
        // Before we begin showing loading view, check to see if we are in the correct state that we should perform this change.
        // This is a safety check in case this function gets called multiple times. We don't want the UI to flicker by changing multiple times.
        guard let currentlyDisplayedInAppWebView = inAppMessageView, messageRenderingLoadingView == nil else {
            return onComplete()
        }

        // To provide the user with feedback indicating a new message is being rendered, show an activity indicator while the new message is loading.
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.startAnimating()
        activityIndicator.isHidden = true // start hidden so when we add the subview, it does not cause a flicker in the UI. Wait to show it when the animation begins.

        addSubview(activityIndicator)
        assert(messageRenderingLoadingView != nil, "Expect activity indicator to be added as a subview")

        // Set autolayout constraints to position the activity indicator.
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            activityIndicator.widthAnchor.constraint(equalTo: widthAnchor),
            activityIndicator.heightAnchor.constraint(equalTo: heightAnchor)
        ])

        animateFadeInOutInlineView(fromView: currentlyDisplayedInAppWebView, toView: activityIndicator) {
            onComplete()
        }
    }

    private func animateHeight(to height: CGFloat) {
        // this function can be called multiple times in short period of time so we could be in the middle of 1 animation. Cancel the current one and start new.
        runningHeightChangeAnimation?.stopAnimation(true)

        runningHeightChangeAnimation = UIViewPropertyAnimator(duration: 0.3, curve: .easeIn, animations: {
            self.heightConstraint?.constant = height // Changing the height in animation block indicates we want to animate the height change.

            // Since we modified constraint, perform a UI refresh to apply the change.
            // It's important that we call layoutIfNeeded on the topmost superview in the hierarchy. During development, there were animiation issues if layoutIfNeeded was called on a different superview then the root.
            // Example, given this UI:
            // UIViewController
            // └── UIStackView
            //    └── InAppMessageView
            // ...If we call layoutIfNeeded on superview (UIStackView), the animation will not work as expected.
            // This is also why it's important that we do QA testing on the inline View when it's nested in a UIStackView.
            self.getRootSuperview()?.layoutIfNeeded()
        })

        runningHeightChangeAnimation?.startAnimation()
    }

    // Takes in 2 Views. In 1 single animation, fades in 1 View while fading out the other.
    private func animateFadeInOutInlineView(fromView: UIView, toView: UIView, onComplete: (() -> Void)?) {
        runningCrossFadeAnimation?.stopAnimation(true) // cancel previous fade animation if there is one to assert this one will be called.

        // Set an initial state for `toView` to begin the animation. Make sure the View is not hidden and is fully opaque.
        toView.isHidden = false
        toView.alpha = 0

        // These are the final values that we are looking for after the animation.
        runningCrossFadeAnimation = UIViewPropertyAnimator(duration: 0.1, curve: .linear, animations: {
            fromView.alpha = 0
            toView.alpha = 1
        })

        runningCrossFadeAnimation?.addCompletion { _ in
            fromView.isHidden = true
            onComplete?()
        }

        runningCrossFadeAnimation?.startAnimation()
    }
}
