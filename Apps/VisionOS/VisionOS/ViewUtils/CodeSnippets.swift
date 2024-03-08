import Foundation
import MarkdownUI

func propertiesToTutorialString(_ properties: [Property], linePrefix: String = "") -> String {
    var res = "["
    var sep = ""
    properties.forEach { p in
        let propertyName = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let propertyValue = p.value
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
    if profile.properties.filter({ p in
        !p.name.isEmpty
    }).isEmpty {
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
      data: \(propertiesToTutorialString(profile.properties, linePrefix: "\t\t")))
    """
}

func trackAsText(withEvent event: Event) -> String {
    if event.properties.filter({ p in
        !p.name.isEmpty
    }).isEmpty {
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
      data: \(propertiesToTutorialString(event.properties, linePrefix: "\t\t")))
    """
}
