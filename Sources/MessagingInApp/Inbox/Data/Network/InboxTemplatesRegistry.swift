import Foundation

/// Raw template registry returned by `GET /api/v1/templates`.
///
/// The gist/network layer stays **Jist-agnostic**: it hands back the registry as raw JSON
/// (`{ name: [versions] }`) without decoding to Jist types. The inbox/UI module is responsible
/// for interpreting the version payloads into whatever rendering types it needs.
///
/// `raw` preserves the full decoded JSON object exactly as received so nested objects, arrays,
/// numbers, and bools are not flattened.
struct InboxTemplatesRegistry: Equatable {
    /// Full raw JSON object as returned by the server: `{ "<templateName>": [ <version>, ... ] }`.
    let raw: [String: Any]

    init(raw: [String: Any]) {
        self.raw = raw
    }

    /// Template names present in the registry.
    var templateNames: [String] {
        Array(raw.keys)
    }

    /// Returns the raw version payloads for a given template name, or nil if absent.
    func versions(forTemplate name: String) -> [Any]? {
        raw[name] as? [Any]
    }

    /// Parses a raw JSON object into a registry. Returns nil if the payload is not a JSON object.
    static func from(jsonData: Data) -> InboxTemplatesRegistry? {
        guard let object = try? JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed]) as? [String: Any] else {
            return nil
        }
        return InboxTemplatesRegistry(raw: object)
    }

    static func == (lhs: InboxTemplatesRegistry, rhs: InboxTemplatesRegistry) -> Bool {
        NSDictionary(dictionary: lhs.raw).isEqual(to: rhs.raw)
    }
}
