import UIKit

// MARK: - UITextFieldDelegate

extension LocationTestViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // Allow backspace
        if string.isEmpty {
            return true
        }

        // Allow digits, decimal point, and leading minus (for negative coordinates)
        let allowedCharacters = CharacterSet(charactersIn: "0123456789.-")
        let characterSet = CharacterSet(charactersIn: string)
        guard allowedCharacters.isSuperset(of: characterSet) else {
            return false
        }

        // Get the resulting string
        let currentText = textField.text ?? ""
        guard let textRange = Range(range, in: currentText) else {
            return true
        }
        let updatedText = currentText.replacingCharacters(in: textRange, with: string)

        // Minus only at the start and at most one
        if updatedText.contains("-") {
            guard updatedText.hasPrefix("-"), updatedText.filter({ $0 == "-" }).count == 1 else {
                return false
            }
        }

        // Only one decimal point
        let decimalCount = updatedText.filter { $0 == "." }.count
        if decimalCount > 1 {
            return false
        }

        return true
    }
}
