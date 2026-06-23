import Foundation
import Jist

/// Decodes the Visual Inbox data layer's raw JSON inputs into the concrete types `JistView`
/// expects: a versioned templates registry, per-message `[String: JistValue]` data, and a
/// `[String: JistValue]` theme.
///
/// The data layer hands the overlay loosely-typed Foundation values (`[String: Any]`) on purpose so
/// the network/data layer stays Jist-agnostic. This is the single place that bridges those into
/// Jist's input types. Decoding is best-effort and never throws: a malformed/unknown entry is
/// skipped rather than failing the whole render (mirrors the Jist Example fixture loaders).
enum VisualInboxJistDecoder {
    private static let decoder = JSONDecoder()

    /// Decodes the raw templates registry (`{ "<name>": [ <versionObject>, ... ] }`) into
    /// `[String: [JistTemplate]]`. `$schema` and any non-array / non-decodable entries are skipped.
    static func decodeTemplates(_ raw: [String: Any]?) -> [String: [JistTemplate]] {
        guard let raw = raw else { return [:] }
        var result: [String: [JistTemplate]] = [:]
        for (name, value) in raw {
            guard let versions = value as? [Any] else { continue }
            var templates: [JistTemplate] = []
            for version in versions {
                guard JSONSerialization.isValidJSONObject(version),
                      let data = try? JSONSerialization.data(withJSONObject: version),
                      let template = try? decoder.decode(JistTemplate.self, from: data) else { continue }
                templates.append(template)
            }
            if !templates.isEmpty {
                result[name] = templates
            }
        }
        return result
    }

    /// Decodes a message's typed `properties` (`[String: Any]`) into `[String: JistValue]` for the
    /// renderer's `data` argument. Returns an empty dictionary if the payload can't be encoded.
    static func decodeData(_ properties: [String: Any]) -> [String: JistValue] {
        guard JSONSerialization.isValidJSONObject(properties),
              let data = try? JSONSerialization.data(withJSONObject: properties),
              let decoded = try? decoder.decode([String: JistValue].self, from: data) else {
            return [:]
        }
        return decoded
    }

    /// Decodes the branding theme tokens (`[String: Any]`) into `[String: JistValue]` for the
    /// renderer's `theme` argument. Returns an empty dictionary if unavailable/undecodable.
    static func decodeTheme(_ raw: [String: Any]?) -> [String: JistValue] {
        guard let raw = raw,
              JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let decoded = try? decoder.decode([String: JistValue].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
