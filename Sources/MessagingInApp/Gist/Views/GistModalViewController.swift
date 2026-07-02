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
    private var isKeyboardVisible = false

    func setup(position: MessagePosition) {
        gistView.delegate = self
        self.position = position
        view.addSubview(gistView)
        setConstraints()
        registerKeyboardObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func registerKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }

        isKeyboardVisible = true
        let keyboardTop = view.frame.height - keyboardFrame.height
        let gistViewBottom = gistView.frame.maxY

        setWebViewScrollEnabled(false)

        if gistViewBottom > keyboardTop {
            let overlap = gistViewBottom - keyboardTop
            verticalConstraint.constant -= overlap
            UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curveValue << 16), animations: {
                self.view.layoutIfNeeded()
            })
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }

        isKeyboardVisible = false
        verticalConstraint.constant = 0
        setWebViewScrollEnabled(true)
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curveValue << 16), animations: {
            self.view.layoutIfNeeded()
        })
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
        // When the keyboard is visible, ignore height reductions to prevent
        // the modal from shrinking and clipping its content.
        if isKeyboardVisible && height < currentHeight {
            return
        }
        currentHeight = height
        updateViewConstraints()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateViewConstraints()
        super.traitCollectionDidChange(previousTraitCollection)
    }

    override func updateViewConstraints() {
        if currentHeight > view.frame.height {
            heightConstraint.constant = view.frame.height
        } else {
            heightConstraint.constant = currentHeight
        }
        widthConstraint.constant = view.frame.width
        super.updateViewConstraints()
    }

    func action(message: Message, currentRoute: String, action: String, name: String) {}

    private func setWebViewScrollEnabled(_ enabled: Bool) {
        guard let webView = gistView.subviews.first(where: { $0 is WKWebView }) as? WKWebView else { return }
        webView.scrollView.isScrollEnabled = enabled
    }
}
