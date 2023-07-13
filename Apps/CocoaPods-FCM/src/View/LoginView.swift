import CioTracking
import SwiftUI

struct LoginView: View {
    @State private var firstNameText: String = ""
    @State private var emailText: String = ""

    @State private var errorMessage: String?
    @State private var showSettings: Bool = false

    @EnvironmentObject var userManager: UserManager

    var body: some View {
        ZStack {
            VStack {
                SettingsButton {
                    showSettings = true
                }
                .setAppiumId("Settings")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 10)
                Spacer()
            }.sheet(isPresented: $showSettings) {
                SettingsView {
                    showSettings = false
                }
            }

            VStack(spacing: 40) { // This view container will be in center of screen.
                TextField("First name", text: $firstNameText).setAppiumId("First Name Input")
                TextField("Email", text: $emailText).setAppiumId("Email Input")
                ColorButton("Login") {
                    // first name is optional

                    // this is good practice when using the Customer.io SDK as you cannot identify a profile with an empty string.
                    guard !emailText.isEmpty else {
                        errorMessage = "Email address is required."
                        return
                    }

                    CustomerIO.shared.identify(identifier: emailText, body: [
                        "email": emailText,
                        "first_name": firstNameText
                    ])

                    userManager.userLoggedIn(email: emailText)
                }.setAppiumId("Login Button")
                Button("Generate random login") {
                    firstNameText = ""
                    emailText = "\(String.random(length: 10))@customer.io"
                }.setAppiumId("Random Login Button")
            }
            .padding([.leading, .trailing], 50)

            VStack { // This view container will be on the bottom of the screen
                Spacer() // Spacers is how you push views to top or bottom of screen.
                EnvironmentText()
            }
        }.alert(isPresented: .notNil(errorMessage)) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage!),
                dismissButton: .default(Text("OK")) {
                    errorMessage = nil
                }
            )
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
}
