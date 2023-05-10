import Foundation

extension String {
    
    static func generateRandomString(ofLength length : Int = 15) -> Self{
        let letters = "AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890"
        let randomWord = (String((0..<length).map{ _ in letters.randomElement()! }))
        return randomWord
    }
}
