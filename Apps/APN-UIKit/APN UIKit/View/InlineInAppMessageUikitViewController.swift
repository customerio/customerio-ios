import CioMessagingInApp
import UIKit

extension UIColor {
    static let lightBlue = UIColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1.0)
}

class InlineInAppMessageUikitViewController: BaseViewController {
    static func newInstance() -> InlineInAppMessageUikitViewController {
        UIStoryboard.getViewController(identifier: "InlineInAppMessageUikitViewController")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
    }

    private let stickyHeaderMessage = InlineMessageUIView(elementId: "sticky-header")
    private let inlineMessage = InlineMessageUIView(elementId: "inline")
    private let belowFoldMessage = InlineMessageUIView(elementId: "below-fold")

    private let scrollView = UIScrollView()
    private let contentStackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. Add sticky header (non-scrollable)
        view.addSubview(stickyHeaderMessage)
        stickyHeaderMessage.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stickyHeaderMessage.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stickyHeaderMessage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stickyHeaderMessage.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // 2. Add scroll view for the remaining content
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: stickyHeaderMessage.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        // 3. Inside the scroll view, place a vertical stack view
        scrollView.addSubview(contentStackView)

        contentStackView.axis = .vertical
        contentStackView.alignment = .fill
        contentStackView.spacing = 10

        contentStackView.isLayoutMarginsRelativeArrangement = true
        contentStackView.layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)

        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),

            // Match the stack view's width to the scroll view's visible width
            contentStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        // 4. Add content to stack view (scrollable portion)
        contentStackView.addArrangedSubview(UICardView())
        contentStackView.addArrangedSubview(UIRectangleView())
        contentStackView.addArrangedSubview(UISquaresView())

        contentStackView.addArrangedSubview(inlineMessage)

        contentStackView.addArrangedSubview(UICardView())
        contentStackView.addArrangedSubview(UIRectangleView())

        contentStackView.addArrangedSubview(UICardView())
        contentStackView.addArrangedSubview(UIRectangleView())

        contentStackView.addArrangedSubview(belowFoldMessage)
    }
}

private class UIRectangleView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .lightBlue

        // Force height to 160
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 160).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class UICardView: UIStackView {
    override init(frame: CGRect) {
        super.init(frame: frame)

        axis = .horizontal
        alignment = .top
        spacing = 20
        distribution = .fill
        translatesAutoresizingMaskIntoConstraints = false

        let leftView = UIView()
        leftView.backgroundColor = .lightBlue
        leftView.layer.cornerRadius = 8
        leftView.translatesAutoresizingMaskIntoConstraints = false
        leftView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        leftView.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let rightStack = UIStackView()
        rightStack.axis = .vertical
        rightStack.alignment = .leading
        rightStack.distribution = .fill
        rightStack.spacing = 5
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        let bar1 = makeBar(width: 120, height: 15)
        let bar2 = makeBar(width: 100, height: 15)
        let spacer = makeSpacer(height: 15)
        let bar3 = makeBar(width: 80, height: 30)

        rightStack.addArrangedSubview(bar1)
        rightStack.addArrangedSubview(bar2)
        rightStack.addArrangedSubview(spacer)
        rightStack.addArrangedSubview(bar3)

        addArrangedSubview(leftView)
        addArrangedSubview(rightStack)

        heightAnchor.constraint(equalToConstant: 120).isActive = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeBar(width: CGFloat, height: CGFloat) -> UIView {
        let bar = UIView()
        bar.backgroundColor = .lightBlue
        bar.layer.cornerRadius = 4
        bar.translatesAutoresizingMaskIntoConstraints = false

        bar.widthAnchor.constraint(equalToConstant: width).isActive = true
        bar.heightAnchor.constraint(equalToConstant: height).isActive = true
        return bar
    }

    private func makeSpacer(height: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
    }
}

private class UISquaresView: UIStackView {
    override init(frame: CGRect) {
        super.init(frame: frame)

        axis = .horizontal
        distribution = .fillEqually
        alignment = .fill
        spacing = 0
        translatesAutoresizingMaskIntoConstraints = false

        let square1 = UIView()
        square1.backgroundColor = .lightBlue

        let square2 = UIView()
        square2.backgroundColor = .lightBlue

        let square3 = UIView()
        square3.backgroundColor = .lightBlue

        addArrangedSubview(square1)
        addArrangedSubview(square2)
        addArrangedSubview(square3)

        heightAnchor.constraint(equalToConstant: 160).isActive = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
