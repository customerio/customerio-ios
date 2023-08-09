// swiftlint:disable line_length

// swiftformat modifies this file and makes it break compilation.
// Because the file was not written for us and we don't plan on modifying it, disable formatting for this file.
// swiftformat:disable all

/*
 Copyright 2018 Read Evaluate Press, LLC

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
// swiftlint:enable line_length

#if canImport(Foundation)
import Foundation
#endif

#if swift(>=5.1)
@frozen public struct AnyEncodable: Encodable {
    public let value: Any

    public init<T>(_ value: T?) {
        self.value = value ?? ()
    }
}
#else
public struct AnyEncodable: Encodable {
    public let value: Any

    public init<T>(_ value: T?) {
        self.value = value ?? ()
    }
}
#endif

// swiftlint:disable type_name
#if swift(>=4.2)
@usableFromInline
protocol _AnyEncodable {
    var value: Any { get }
    init<T>(_ value: T?)
}
#else
protocol _AnyEncodable {
    var value: Any { get }
    init<T>(_ value: T?)
}
#endif
// swiftlint:enable type_name

extension AnyEncodable: _AnyEncodable {}

// MARK: - Encodable

// swiftlint:disable cyclomatic_complexity function_body_length
extension _AnyEncodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        case let number as NSNumber:
            try encode(nsnumber: number, into: &container)
#endif
#if canImport(Foundation)
        case is NSNull:
            try container.encodeNil()
#endif
        case is Void:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let int8 as Int8:
            try container.encode(int8)
        case let int16 as Int16:
            try container.encode(int16)
        case let int32 as Int32:
            try container.encode(int32)
        case let int64 as Int64:
            try container.encode(int64)
        case let uint as UInt:
            try container.encode(uint)
        case let uint8 as UInt8:
            try container.encode(uint8)
        case let uint16 as UInt16:
            try container.encode(uint16)
        case let uint32 as UInt32:
            try container.encode(uint32)
        case let uint64 as UInt64:
            try container.encode(uint64)
        case let float as Float:
            try container.encode(float)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
#if canImport(Foundation)
        case let date as Date:
            try container.encode(date)
        case let url as URL:
            try container.encode(url)
#endif
        case let array as [Any?]:
            try container.encode(array.map { AnyEncodable($0) })
        case let dictionary as [String: Any?]:
            try container.encode(dictionary.mapValues { AnyEncodable($0) })
        case let encodable as Encodable:
            try encodable.encode(to: encoder)
        default:
            let context = EncodingError.Context(codingPath: container.codingPath,
                                                debugDescription: "AnyEncodable value cannot be encoded")
            throw EncodingError.invalidValue(value, context)
        }
    }

    #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
    private func encode(nsnumber: NSNumber, into container: inout SingleValueEncodingContainer) throws {
        switch CFNumberGetType(nsnumber) {
        case .charType:
            try container.encode(nsnumber.boolValue)
        case .sInt8Type:
            try container.encode(nsnumber.int8Value)
        case .sInt16Type:
            try container.encode(nsnumber.int16Value)
        case .sInt32Type:
            try container.encode(nsnumber.int32Value)
        case .sInt64Type:
            try container.encode(nsnumber.int64Value)
        case .shortType:
            try container.encode(nsnumber.uint16Value)
        case .longType:
            try container.encode(nsnumber.uint32Value)
        case .longLongType:
            try container.encode(nsnumber.uint64Value)
        case .intType, .nsIntegerType, .cfIndexType:
            try container.encode(nsnumber.intValue)
        case .floatType, .float32Type:
            try container.encode(nsnumber.floatValue)
        case .doubleType, .float64Type, .cgFloatType:
            try container.encode(nsnumber.doubleValue)
        #if swift(>=5.0)
        @unknown default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "NSNumber cannot be encoded because its type is not handled")
            throw EncodingError.invalidValue(nsnumber, context)
        #endif
        }
    }
    #endif
}

extension AnyEncodable: Equatable {
    public static func == (lhs: AnyEncodable, rhs: AnyEncodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case is (Void, Void):
            return true
        case let (lhs as Bool, rhs as Bool):
            return lhs == rhs
        case let (lhs as Int, rhs as Int):
            return lhs == rhs
        case let (lhs as Int8, rhs as Int8):
            return lhs == rhs
        case let (lhs as Int16, rhs as Int16):
            return lhs == rhs
        case let (lhs as Int32, rhs as Int32):
            return lhs == rhs
        case let (lhs as Int64, rhs as Int64):
            return lhs == rhs
        case let (lhs as UInt, rhs as UInt):
            return lhs == rhs
        case let (lhs as UInt8, rhs as UInt8):
            return lhs == rhs
        case let (lhs as UInt16, rhs as UInt16):
            return lhs == rhs
        case let (lhs as UInt32, rhs as UInt32):
            return lhs == rhs
        case let (lhs as UInt64, rhs as UInt64):
            return lhs == rhs
        case let (lhs as Float, rhs as Float):
            return lhs == rhs
        case let (lhs as Double, rhs as Double):
            return lhs == rhs
        case let (lhs as String, rhs as String):
            return lhs == rhs
        case let (lhs as [String: AnyEncodable], rhs as [String: AnyEncodable]):
            return lhs == rhs
        case let (lhs as [AnyEncodable], rhs as [AnyEncodable]):
            return lhs == rhs
        default:
            return false
        }
    }
}
// swiftlint:enable cyclomatic_complexity function_body_length

extension AnyEncodable: CustomStringConvertible {
    public var description: String {
        switch value {
        case is Void:
            return String(describing: nil as Any?)
        case let value as CustomStringConvertible:
            return value.description
        default:
            return String(describing: value)
        }
    }
}

extension AnyEncodable: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch value {
        case let value as CustomDebugStringConvertible:
            return "AnyEncodable(\(value.debugDescription))"
        default:
            return "AnyEncodable(\(description))"
        }
    }
}

extension AnyEncodable: ExpressibleByNilLiteral {}
extension AnyEncodable: ExpressibleByBooleanLiteral {}
extension AnyEncodable: ExpressibleByIntegerLiteral {}
extension AnyEncodable: ExpressibleByFloatLiteral {}
extension AnyEncodable: ExpressibleByStringLiteral {}
#if swift(>=5.0)
extension AnyEncodable: ExpressibleByStringInterpolation {}
#endif
extension AnyEncodable: ExpressibleByArrayLiteral {}
extension AnyEncodable: ExpressibleByDictionaryLiteral {}

extension _AnyEncodable {
    public init(nilLiteral _: ()) {
        self.init(nil as Any?)
    }

    public init(booleanLiteral value: Bool) {
        self.init(value)
    }

    public init(integerLiteral value: Int) {
        self.init(value)
    }

    public init(floatLiteral value: Double) {
        self.init(value)
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(value)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(arrayLiteral elements: Any...) {
        self.init(elements)
    }

    public init(dictionaryLiteral elements: (AnyHashable, Any)...) {
        self.init([AnyHashable: Any](elements, uniquingKeysWith: { first, _ in first }))
    }
}
