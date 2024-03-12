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
        !p.name.isEmpty && !p.value.isEmpty
    }.map { p in
        Property(
            name: p.name
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
        \(sep)"\(p.name)": "\(p.value)"
        """
        sep = ", "
    }
    res += "]"
    return res
}
