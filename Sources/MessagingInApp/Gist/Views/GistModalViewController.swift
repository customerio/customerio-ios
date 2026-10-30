import CioInternalCommon
import Foundation
import UIKit
import WebKit

/*
 Important that automatic screenview events are not tracked when Modal is showing on screen. Automatic screenview events sets the page rule route in the in-app SDK. When the page rule route changes, our SDK performs logic such as dismissing in-app messages.
 */
class GistModalViewController: UIViewController, GistViewDelegate, DoNotTrackScreenViewEvent {
    var currentHeight: CGFloat = 0.0
    weak var gistView: GistView!
    var position: MessagePosition!
    var verticalConstraint,
        horizontalConstraint,
        widthConstraint,
        heightConstraint,
        bottomConstraint: NSLayoutConstraint!
    /// How far the keyboard reaches up into this view. Zero while the keyboard is hidden.
    private(set) var keyboardOverlap: CGFloat = 0

    func setup(position: MessagePosition) {
        gistView.delegate = self
        self.position = position
        view.addSubview(gistView)
        setConstraints()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setConstraints() {
        view.translatesAutoresizingMaskIntoConstraints = false
        gistView.translatesAutoresizingMaskIntoConstraints = false

        let maxWidthConstraint = gistView.widthAnchor.constraint(lessThanOrEqualToConstant: 414)
        widthConstraint = gistView.widthAnchor.constraint(equalToConstant: view.frame.width)
        heightConstraint = gistView.heightAnchor.constraint(equalToConstant: gistView.frame.height)
        horizontalConstraint = gistView.centerXAnchor.constraint(equalTo: view.centerXAnchor)

        switch position {
        case .top:
            verticalConstraint = gistView.topAnchor.constraint(equalTo: view.topAnchor)
        case .center:
            verticalConstraint = gistView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        case .bottom:
            verticalConstraint = gistView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        case .none:
            verticalConstraint = gistView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        }

        widthConstraint.priority = UILayoutPriority.defaultHigh
        maxWidthConstraint.priority = UILayoutPriority.required
        NSLayoutConstraint.activate([horizontalConstraint,
                                     verticalConstraint,
                                     maxWidthConstraint,
                                     widthConstraint,
                                     heightConstraint])
    }

    func sizeChanged(message: Message, width: CGFloat, height: CGFloat) {
        currentHeight = height
        view.setNeedsLayout()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateConstraintConstants()
    }

    private func updateConstraintConstants() {
        guard let heightConstraint, let widthConstraint, let verticalConstraint else { return }

        let layout = Self.layout(
            position: position ?? .center,
            viewHeight: view.frame.height,
            contentHeight: currentHeight,
            keyboardOverlap: keyboardOverlap,
            topInset: view.safeAreaInsets.top
        )
        if heightConstraint.constant != layout.height {
            heightConstraint.constant = layout.height
        }
        if verticalConstraint.constant != layout.verticalOffset {
            verticalConstraint.constant = layout.verticalOffset
        }
        if widthConstraint.constant != view.frame.width {
            widthConstraint.constant = view.frame.width
        }
    }

    /// Height and vertical offset for the message.
    ///
    /// With the keyboard up, the message moves just far enough to clear it and only gets shorter when
    /// it still does not fit. The move never pushes it past the top safe area, though tall centered
    /// content can still reach above it, as it does without a keyboard. If the bottom of the message
    /// stays behind the keyboard, WebKit scrolls the content up inside the fixed frame to show the
    /// focused field, which cuts off the top of the message.
    static func layout(
        position: MessagePosition,
        viewHeight: CGFloat,
        contentHeight: CGFloat,
        keyboardOverlap: CGFloat,
        topInset: CGFloat
    ) -> (height: CGFloat, verticalOffset: CGFloat) {
        guard keyboardOverlap > 0 else {
            return (min(contentHeight, viewHeight), 0)
        }

        switch position {
        case .top:
            // Already pinned to the top, so it can only get shorter.
            return (min(contentHeight, max(0, viewHeight - keyboardOverlap)), 0)
        case .center:
            let height = min(contentHeight, max(0, viewHeight - keyboardOverlap - topInset))
            // Centered in the space between the safe area top and the keyboard, and never lower than
            // it sits without one, which a short keyboard toolbar would otherwise cause.
            return (height, min(0, (topInset - keyboardOverlap) / 2))
        case .bottom:
            let height = min(contentHeight, max(0, viewHeight - keyboardOverlap - topInset))
            return (height, -keyboardOverlap)
        }
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let info = notification.userInfo,
              let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let screen = view.window?.screen
        else { return }
        // The notification's object is the screen the keyboard is on.
        if let keyboardScreen = notification.object as? UIScreen, keyboardScreen !== screen { return }

        // The modal has its own window, so the keyboard frame has to come out of screen space first.
        let keyboardFrame = view.convert(endFrame, from: screen.coordinateSpace)
        let overlap = Self.keyboardOverlap(keyboardFrame: keyboardFrame, viewBounds: view.bounds)
        guard overlap != keyboardOverlap else { return }
        keyboardOverlap = overlap

        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        view.setNeedsLayout()
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16), animations: { [weak self] in
            self?.view.layoutIfNeeded()
        }, completion: { [weak self] _ in
            // WebKit can leave the content scrolled after the field it revealed is no longer covered.
            guard let self, self.keyboardOverlap == 0 else { return }
            self.webView?.scrollView.setContentOffset(.zero, animated: true)
        })
    }

    /// How much of the bottom of the view the keyboard covers. A floating keyboard on iPad can sit
    /// beside or above the window, which covers nothing.
    static func keyboardOverlap(keyboardFrame: CGRect, viewBounds: CGRect) -> CGFloat {
        guard keyboardFrame.intersects(viewBounds) else { return 0 }
        return max(0, viewBounds.maxY - keyboardFrame.minY)
    }

    private var webView: WKWebView? {
        gistView?.subviews.first { $0 is WKWebView } as? WKWebView
    }

    func action(message: Message, currentRoute: String, action: String, name: String) {}
}
