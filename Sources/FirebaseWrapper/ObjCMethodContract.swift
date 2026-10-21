import Foundation
import ObjectiveC

/// An Objective-C type, as it appears in a method's runtime type encoding.
enum ObjCType: Equatable {
    case void
    case object
    case block
    case bool

    // `BOOL` is `bool` on arm64 and `signed char` on x86_64 simulators.
    private static var boolEncoding: String {
        #if arch(x86_64)
        return "c"
        #else
        return "B"
        #endif
    }

    fileprivate func matches(_ encoding: String) -> Bool {
        let type = Self.strippingQualifiers(encoding)
        switch self {
        case .void: return type == "v"
        case .bool: return type == Self.boolEncoding
        // Objects may carry a class name (`@"NSData"`); blocks may carry a signature (`@?<v@?@@>`).
        case .object: return type == "@" || (type.hasPrefix("@\"") && type.hasSuffix("\""))
        case .block: return type.hasPrefix("@?")
        }
    }

    // `const`, `in`, `inout`, `out`, `bycopy`, `byref` and `oneway` qualifiers don't change the ABI.
    private static func strippingQualifiers(_ encoding: String) -> String {
        String(encoding.drop(while: { "rnNoORV".contains($0) }))
    }
}

/// The expected Objective-C signature of a method the adapter calls on Firebase.
///
/// Checked against the runtime's type encoding before the SDK casts a Firebase object to one of its `@objc` protocols,
/// so a method that exists under the same selector with different types is refused instead of called.
/// Type encodings can't describe a block's own parameters, an object's class or nullability; those are covered by
/// testing against real Firebase versions.
struct ObjCMethodContract {
    enum Kind {
        case instance
        case `class`
    }

    let selector: Selector
    let kind: Kind
    let returnType: ObjCType
    let argumentTypes: [ObjCType]

    init(_ selector: Selector, _ kind: Kind = .instance, returns returnType: ObjCType, arguments argumentTypes: [ObjCType] = []) {
        self.selector = selector
        self.kind = kind
        self.returnType = returnType
        self.argumentTypes = argumentTypes
    }

    func isSatisfied(by objectClass: AnyClass) -> Bool {
        let method: Method?
        switch kind {
        case .instance: method = class_getInstanceMethod(objectClass, selector)
        case .class: method = class_getClassMethod(objectClass, selector)
        }
        guard let method = method else { return false }

        // The runtime counts `self` and `_cmd` as the first two arguments.
        guard method_getNumberOfArguments(method) == UInt32(argumentTypes.count + 2) else { return false }
        guard returnType.matches(Self.encoding(method_copyReturnType(method))) else { return false }
        for (index, argumentType) in argumentTypes.enumerated() {
            guard let argument = method_copyArgumentType(method, UInt32(index + 2)),
                  argumentType.matches(Self.encoding(argument))
            else {
                return false
            }
        }
        return true
    }

    // Takes ownership of a type string the runtime allocated.
    private static func encoding(_ pointer: UnsafeMutablePointer<CChar>) -> String {
        defer { free(pointer) }
        return String(cString: pointer)
    }
}

extension Array where Element == ObjCMethodContract {
    /// The contracts `objectClass` doesn't satisfy, empty when it satisfies all of them.
    func unsatisfied(by objectClass: AnyClass) -> [ObjCMethodContract] {
        filter { !$0.isSatisfied(by: objectClass) }
    }
}
