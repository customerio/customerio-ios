import Foundation

/**
 Version of NSCoder you can use in automated tests.

 Convenient when you want to write tests against UIKit UIView classes.

 Usage:
 ```
 let viewToTest = InlineMessageUIView(coder: EmptyNSCoder())!
 ```
 */
public class EmptyNSCoder: NSCoder {
    override public var allowsKeyedCoding: Bool {
        true
    }

    override public func containsValue(forKey key: String) -> Bool {
        false
    }

    override public func decodeObject(forKey key: String) -> Any? {
        nil
    }

    override public func encode(_ objv: Any?, forKey key: String) {}

    override public func decodeBool(forKey key: String) -> Bool {
        false
    }

    override public func decodeInt64(forKey key: String) -> Int64 {
        0
    }

    override public func decodeDouble(forKey key: String) -> Double {
        0.0
    }

    override public func decodeFloat(forKey key: String) -> Float {
        0.0
    }

    override public func decodeInt32(forKey key: String) -> Int32 {
        0
    }

    override public func decodeInteger(forKey key: String) -> Int {
        0
    }
}
