import Foundation
import UIKit

enum AlertType: String {
    case info = "Info"
    case error = "Error"
}

extension UIViewController {
    func showAlert(withMessage message: String, _ type: AlertType = .info, action buttonAction: @escaping () -> Void = {}) {
        let dialogMessage = UIAlertController(title: type.rawValue, message: message, preferredStyle: .alert)
        
        let okAction = UIAlertAction(title: "OK", style: .default, handler: { _ in
            buttonAction()
        })
        dialogMessage.addAction(okAction)
        present(dialogMessage, animated: true, completion: nil)
    }
    
    func dismissKeyboardOnTap() {
        let tapGesture = UITapGestureRecognizer(target: self,
                                                action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
    }
    
    @objc func dismissKeyboard() {
        view.endEditing(true)
    }
}
