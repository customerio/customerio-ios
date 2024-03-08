import SwiftUI

@ViewBuilder func button(
    forLink link: InlineNavigationLink,
    state: AppState
) -> some View {
    Button {
        state.navigationPath = [link]
    } label: {
        Text(link.menuTitle)
        if state.visitedLinks.contains(link) {
            Image(systemName: "checkmark.circle.fill")
        }
    }
}

func getEnabledNavigationLinks(_ state: AppState) -> [InlineNavigationLink] {
    if state.workspaceSettings.isSet(), state.profile.loggedIn {
        return InlineNavigationLink.allCases
    }

    if state.workspaceSettings.isSet() {
        return InlineNavigationLink.preIdentifyLinks
    }

    return InlineNavigationLink.preInitializationLinks
}

struct TutorialsMenuView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        Menu {
            ForEach(getEnabledNavigationLinks(state), id: \.self) { link in
                button(forLink: link, state: state)
            }
        } label: {
            Image(systemName: "menubar.dock.rectangle")
        }
    }
}

#Preview {
    TutorialsMenuView()
}
