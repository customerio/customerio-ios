import CioInternalCommon
import Foundation

/// Merges profile enrichment provider attributes; only primitive values (String, Number, Bool) from providers are included.
enum ProfileEnrichmentAttributesMerger {
    /// Collects attributes from all providers, keeping only primitive values (String, Number, Bool).
    static func gatherEnrichmentAttributes(registry: ProfileEnrichmentRegistry) -> [String: Any] {
        var result: [String: Any] = [:]
        for provider in registry.getAll() {
            guard let attrs = provider.getProfileEnrichmentAttributes() else { continue }
            for (key, value) in attrs where isPrimitive(value) {
                result[key] = value
            }
        }
        return result
    }

    /// String, Number, Boolean only. Other types are skipped.
    private static func isPrimitive(_ value: Any) -> Bool {
        switch value {
        case is String, is Bool:
            return true
        case is any Numeric:
            return true
        default:
            return false
        }
    }
}
