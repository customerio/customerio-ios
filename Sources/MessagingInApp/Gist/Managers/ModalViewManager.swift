import UIKit

public enum MessagePosition: String {
    case top
    case center
    case bottom
}

class ModalViewManager {
    var window: UIWindow?
    var viewController: GistModalViewController!
    var position: MessagePosition
    var overlayColor: String?
    var colorScheme: ColorScheme

    init(gistView: GistView, position: MessagePosition, overlayColor: String?, colorScheme: ColorScheme = .auto) {
        self.viewController = GistModalViewController()
        viewController.gistView = gistView
        viewController.setup(position: position)
        self.position = position
        self.overlayColor = overlayColor
        self.colorScheme = colorScheme
    }

    func showModalView(completionHandler: @escaping () -> Void) {
        viewController.view.isHidden = true
        window = getUIWindow()
        applyColorSchemeToWindow()
        window?.rootViewController = viewController
        window?.isHidden = false
        var finalPosition: CGFloat = 0

        switch position {
        case .top:
            viewController.view.center.y -= viewController.view.bounds.height
            finalPosition = viewController.view.center.y + viewController.view.bounds.height
        case .center:
            viewController.view.center.y += viewController.view.bounds.height
            finalPosition = viewController.view.center.y - viewController.view.bounds.height
        case .bottom:
            viewController.view.center.y += viewController.view.bounds.height
            finalPosition = viewController.view.center.y - viewController.view.bounds.height
        }

        let overlayColor = UIColor.fromHex(overlayColor) ?? UIColor.black.withAlphaComponent(0.2)
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn], animations: {
            self.viewController.view.center.y = finalPosition
        }, completion: { _ in
            UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseIn], animations: {
                self.viewController.view.backgroundColor = overlayColor
            }, completion: nil)
            completionHandler()
        })

        viewController.view.isHidden = false
    }

    func dismissModalView(completionHandler: @escaping () -> Void) {
        var finalPosition: CGFloat = 0
        switch position {
        case .top:
            finalPosition = viewController.view.center.y - viewController.view.bounds.height
        case .center:
            finalPosition = viewController.view.center.y + viewController.view.bounds.height
        case .bottom:
            finalPosition = viewController.view.center.y + viewController.view.bounds.height
        }

        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseIn], animations: {
            self.viewController.view.backgroundColor = UIColor.black.withAlphaComponent(0)
        }, completion: { _ in
            UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseIn], animations: {
                self.viewController.view.center.y = finalPosition
            }, completion: { _ in
                self.removeModalViewFromScreen()

                completionHandler()
            })
        })
    }

    private func removeModalViewFromScreen() {
        viewController?.view.isHidden = true
        window?.isHidden = true
        viewController.removeFromParent()
        window = nil
    }

    func updateColorScheme(_ newColorScheme: ColorScheme) {
        colorScheme = newColorScheme
        applyColorSchemeToWindow()
    }

    private func applyColorSchemeToWindow() {
        switch colorScheme {
        case .light:
            window?.overrideUserInterfaceStyle = .light
        case .dark:
            window?.overrideUserInterfaceStyle = .dark
        case .auto:
            inheritAppInterfaceStyle()
        }
    }

    private func inheritAppInterfaceStyle() {
        guard let appWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0 !== self.window }) else { return }

        if appWindow.overrideUserInterfaceStyle != .unspecified {
            window?.overrideUserInterfaceStyle = appWindow.overrideUserInterfaceStyle
        } else if let rootVC = appWindow.rootViewController, rootVC.overrideUserInterfaceStyle != .unspecified {
            window?.overrideUserInterfaceStyle = rootVC.overrideUserInterfaceStyle
        }
    }

    private func getUIWindow() -> UIWindow {
        var modalWindow = UIWindow(frame: UIScreen.main.bounds)
        if #available(iOS 13.0, *) {
            for connectedScene in UIApplication.shared.connectedScenes
                where connectedScene.activationState == .foregroundActive {
                if let windowScene = connectedScene as? UIWindowScene {
                    modalWindow = UIWindow(windowScene: windowScene)
                }
            }
        }
        modalWindow.windowLevel = .normal
        return modalWindow
    }
}
