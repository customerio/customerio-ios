import Foundation
import MarkdownUI

func dataToTutorialString(_ data: [String: String], linePrefix: String = "") -> String {
    let keys = data.keys.sorted().reversed()

    if keys.isEmpty {
        return "[:]"
    }

    var res = "["
    var sep = ""
    keys.forEach { key in
        let propertyName = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let propertyValue = data[key]!
            .trimmingCharacters(in: .whitespacesAndNewlines)
        res += """
        \(sep)"\(propertyName)": "\(propertyValue)"
        """
        sep = ", "
    }
    res += "]"
    return res
}

func initializeCodeSnippet(withWorkspaceSettings settings: WorkspaceSettings)
    -> String {
    """
    CustomerIO.initialize(
                siteId: "\(settings.siteId)",
                apiKey: "\(settings.apiKey)",
                region: .\(settings.region),
                configure: nil)
    """
}

func identifyAsText(withProfile profile: Profile) -> String {
    if profile.email.isEmpty, profile.name.isEmpty {
        return
            """
            CustomerIO.shared.identify(
              identifier: "\(profile.id)"
            )
            """
    }
    return """
    CustomerIO.shared.identify(
      identifier: "\(profile.id)",
      data: \(dataToTutorialString(profile.fieldsToDictionay(), linePrefix: "\t\t")))
    """
}

func trackAsText(withEvent event: Event) -> String {
    if event.propertyName.isEmpty, event.propertyValue.isEmpty {
        return
            """
            CustomerIO.shared.track(
              name: "\(event.name)"
            )
            """
    }
    return """
    CustomerIO.shared.track(
      name: "\(event.name)",
      data: \(dataToTutorialString(event.fieldsToDictionay(), linePrefix: "\t\t")))
    """
}
