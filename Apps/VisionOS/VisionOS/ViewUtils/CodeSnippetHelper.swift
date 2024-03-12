import Foundation

extension String {
    func escapeQuotes() -> String {
        replacingOccurrences(of: "\"", with: "\"\"")
    }
}

func propertiesToTutorialString(
    _ properties: [Property],
    linePrefix: String = ""
) -> String {
    let senatizedProperties = properties.filter { p in
        !p.key.isEmpty && !p.value.isEmpty
    }.map { p in
        Property(
            key: p.key
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .escapeQuotes(),
            value: p.value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .escapeQuotes()
        )
    }
    if senatizedProperties.isEmpty {
        return ""
    }

    var res = "["
    var sep = ""
    senatizedProperties.forEach { p in
        res += """
        \(sep)"\(p.key)": "\(p.value)"
        """
        sep = ", "
    }
    res += "]"
    return res
}
