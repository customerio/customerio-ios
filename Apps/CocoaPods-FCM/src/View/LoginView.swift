import CioTracking
import SwiftUI

struct LoginView: View {
    @State private var firstNameText: String = ""
    @State private var emailText: String = ""

    @State private var showSettings: Bool = false

    @EnvironmentObject var userManager: UserManager

    var body: some View {
        ZStack {
            VStack {
                Button("Settings") {
                    showSettings = true
                }
                Spacer()
            }.sheet(isPresented: $showSettings) {
                SettingsView {
                    showSettings = false
                }
            }

            VStack(spacing: 40) { // This view container will be in center of screen.
                TextField("First name", text: $firstNameText)
                TextField("Email", text: $emailText)
                ColorButton(title: "Login") {
                    CustomerIO.shared.identify(identifier: emailText, body: [
                        "first_name": firstNameText
                    ])

                    userManager.userLoggedIn(email: emailText)
                }
                Button("Generate random login") {
                    firstNameText = String.random.capitalized
                    emailText = "\(firstNameText.lowercased())@customer.io"
                }
            }
            .padding([.leading, .trailing], 50)

            VStack { // This view container will be on the bottom of the screen
                Spacer() // Spacers is how you push views to top or bottom of screen.
                EnvironmentText()
            }
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
}
