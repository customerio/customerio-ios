import Foundation
import UIKit

extension UITextField {
    var isTextTrimEmpty: Bool {
        text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? "" == ""
    }
}
