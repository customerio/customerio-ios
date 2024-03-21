import SwiftUI

struct MainScreen: View {
    @ObservedObject var state: AppState = .shared
    var body: some View {
        VStack {
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    MainScreen()
}
