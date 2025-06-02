import CioInternalCommon
import Foundation

extension Dictionary where Key == String, Value == Any {
    /**
     Sanitizes a dictionary by removing JSON-incompatible values like NaN and infinities.
     This prevents JSON serialization errors when sending events with these values.

     - Parameter logger: Logger to log removed values
     - Returns: A new dictionary with all JSON-incompatible values removed
     */
    func sanitizedForJSON(logger: Logger = DIGraphShared.shared.logger) -> [String: Any] {
        var result: [String: Any] = [:]

        for (key, value) in self {
            // If sanitizeValue returns nil, the value is invalid for JSON and we skip it
            if let sanitizedValue = sanitizeValue(value, logger: logger) {
                result[key] = sanitizedValue
            }
        }

        return result
    }

    /**
     Sanitizes a value for JSON serialization.

     - Parameter value: The value to sanitize
     - Returns: The sanitized value, or nil if the value is invalid for JSON (NaN, infinity)
     */
    private func sanitizeValue(_ value: Any, logger: Logger) -> Any? {
        switch value {
        case let number as Double:
            if number.isNaN || number.isInfinite {
                logger.error("Removed unsupported numeric value")
                return nil
            } else {
                return number
            }
        case let number as Float:
            if number.isNaN || number.isInfinite {
                logger.error("Removed unsupported numeric value")
                return nil
            } else {
                return number
            }
        case let dict as [String: Any]:
            let sanitized = dict.sanitizedForJSON(logger: logger)
            return sanitized.isEmpty ? nil : sanitized
        case let array as [Any]:
            let sanitized = sanitizeArray(array, logger: logger)
            return sanitized.isEmpty ? nil : sanitized
        default:
            return value
        }
    }

    /**
     Sanitizes an array by removing JSON-incompatible values.

     - Parameter array: The array to sanitize
     - Returns: A new array with all JSON-incompatible values removed
     */
    private func sanitizeArray(_ array: [Any], logger: Logger) -> [Any] {
        array.compactMap { value in
            sanitizeValue(value, logger: logger)
        }
    }
}

extension Array where Element == Any {
    /**
     Sanitizes an array by removing JSON-incompatible values like NaN and infinities.

     - Returns: A new array with all JSON-incompatible values removed
     */
    func sanitizedForJSON(logger: Logger = DIGraphShared.shared.logger) -> [Any] {
        compactMap { value in
            if let dict = value as? [String: Any] {
                let sanitized = dict.sanitizedForJSON(logger: logger)
                return sanitized.isEmpty ? nil : sanitized
            } else if let array = value as? [Any] {
                let sanitized = array.sanitizedForJSON(logger: logger)
                return sanitized.isEmpty ? nil : sanitized
            } else if let number = value as? Double {
                if number.isNaN || number.isInfinite {
                    logger.error("Removed unsupported numeric value")
                    return nil
                }
                return number
            } else if let number = value as? Float {
                if number.isNaN || number.isInfinite {
                    logger.error("Removed unsupported numeric value")
                    return nil
                }
                return number
            } else {
                return value
            }
        }
    }
}
