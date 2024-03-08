import SwiftUI

struct MainScreen: View {
    @ObservedObject var state: AppState = .shared
    var body: some View {
        VStack {
            Text("Hello, world!")
        }
        .padding()
        .environment(
            \.openURL,
            OpenURLAction { url in
                guard let link = InlineNavigationLink(fromUrl: url) else {
                    return .systemAction
                }
                withAnimation {
                    state.navigationPath = [link]
                }

                return .handled
            }
        )
    }
}

#Preview(windowStyle: .automatic) {
    MainScreen()
}
