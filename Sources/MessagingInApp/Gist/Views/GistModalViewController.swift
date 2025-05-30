import CioInternalCommon
import Foundation
import UIKit

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

    func setup(position: MessagePosition) {
        gistView.delegate = self
        self.position = position
        view.addSubview(gistView)
        setConstraints()
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
}
