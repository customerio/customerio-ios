import Foundation
import UIKit

extension UIViewController {
    
    func showInfoAlert(withMessage message: String) {
        let dialogMessage = UIAlertController(title: "Info", message: message, preferredStyle: .alert)
        
        let okAction = UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
            print("Ok button tapped")
         })
        dialogMessage.addAction(okAction)
        present(dialogMessage, animated: true, completion: nil)
    }
}
