import Foundation
import SwiftUI

extension Binding where Value == Bool {
    // Designed to be used in SwiftUI Previews to populate constructors. May not be appropriate to use in an app.
    static func constant(value: Bool) -> Binding<Bool> {
        Binding(get: { value }, set: { _, _ in })
    }
}

extension Binding {
    func cast<T>(to: @escaping (Value) -> T, from: @escaping (T) -> Value) -> Binding<T> {
        Binding<T> {
            to(self.wrappedValue)
        } set: { newValue, _ in
            self.wrappedValue = from(newValue)
        }
    }

    static func notNil(_ value: Any?) -> Binding<Bool> {
        Binding<Bool>(get: { value != nil }, set: { _, _ in })
    }
}
