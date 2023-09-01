import CioTracking
import SwiftUI
import UserNotifications

struct DashboardView: View {
    enum Subscreen: String {
        case customEvent
        case profileAttribute
        case deviceAttribute
        case settings
    }

    struct BlockingAlert {
        let alertMessage: String
        let callToActionButton: (actionText: String, actionCallback: () -> Void)? // optional button to add to Alert
    }

    @State private var subscreenShown: Subscreen?

    @State private var customEventName: String = ""
    @State private var customEventPropertyName: String = ""
    @State private var customEventPropertyValue: String = ""

    @State private var nonBlockingMessage: String?
    @State private var blockingAlert: BlockingAlert?

    @EnvironmentObject var userManager: UserManager

    var body: some View {
        ZStack {
            VStack {
                SettingsButton {
                    subscreenShown = .settings
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 10)
                Spacer()
            }
            .sheet(isPresented: .constant(subscreenShown == .settings), onDismiss: { subscreenShown = nil }) {
                SettingsView {
                    subscreenShown = nil
                }
            }

            VStack(spacing: 15) {
                if let loggedInUserEmail = userManager.email {
                    Text(loggedInUserEmail)
                }
                Text("What would you like to test?")

                Group {
                    ColorButton("Send Random Event") {
                        switch Int.random(in: 0 ..< 3) {
                        case 0:
                            CustomerIO.shared.track(name: "Order Purchased")
                        case 1:
                            CustomerIO.shared.track(
                                name: "movie_watched",
                                data: [
                                    "movie_name": "The Incredibles"
                                ]
                            )
                        default: // case 2
                            CustomerIO.shared.track(
                                name: "appointmentScheduled",
                                data: [
                                    "appointmentTime": Calendar.current.date(byAdding: .day, value: 7, to: Date())!.epochNoMilliseconds
                                ]
                            )
                        }

                        nonBlockingMessage = "Random event sent"
                    }
                    .setAppiumId("Random Event Button")

                    ColorButton("Send Custom Event") {
                        subscreenShown = .customEvent
                    }.setAppiumId("Custom Event Button")
                        .sheet(isPresented: .constant(subscreenShown == .customEvent), onDismiss: { subscreenShown = nil }) {
                            CustomEventView(close: {
                                subscreenShown = nil
                            })
                        }

                    ColorButton("Set Device Attribute") {
                        subscreenShown = .deviceAttribute
                    }.setAppiumId("Device Attribute Button")
                        .sheet(isPresented: .constant(subscreenShown == .deviceAttribute), onDismiss: { subscreenShown = nil }) {
                            CustomAttributeView(attributeType: .device, close: {
                                subscreenShown = nil
                            })
                        }

                    ColorButton("Set Profile Attribute") {
                        subscreenShown = .profileAttribute
                    }.setAppiumId("Profile Attribute Button")
                        .sheet(isPresented: .constant(subscreenShown == .profileAttribute), onDismiss: { subscreenShown = nil }) {
                            CustomAttributeView(attributeType: .profile, close: {
                                subscreenShown = nil
                            })
                        }

                    ColorButton("Show Push Prompt") {
                        UNUserNotificationCenter.current().getNotificationSettings { settings in
                            switch settings.authorizationStatus {
                            case .authorized:
                                blockingAlert = BlockingAlert(alertMessage: "Push permission already granted", callToActionButton: nil)
                            case .denied:
                                blockingAlert = BlockingAlert(
                                    alertMessage: "Push permission denied. You will need to go into the Settings app to change the push permission for this app.",
                                    callToActionButton: (actionText: "Go to Settings", actionCallback: {
                                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                                    })
                                )
                            case .notDetermined:
                                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                                    if granted {
                                        DispatchQueue.main.async {
                                            UIApplication.shared.registerForRemoteNotifications()
                                        }
                                    }
                                }
                            default: break
                            }
                        }
                    }.setAppiumId("Show Push Prompt Button")
                    ColorButton("Logout") {
                        CustomerIO.shared.clearIdentify()

                        userManager.logout()
                    }.setAppiumId("Log Out Button")
                }

                EnvironmentText()
            }
            .padding()
        }
        // Can only use 1 alert() in a View so we combine the different types of Alerts into 1 function.
        .alert(isPresented: .notNil(blockingAlert)) {
            if let alertCallToAction = blockingAlert!.callToActionButton {
                return Alert(
                    title: Text(blockingAlert!.alertMessage),
                    primaryButton: .default(Text(alertCallToAction.actionText)) {
                        blockingAlert = nil
                        alertCallToAction.actionCallback()
                    },
                    secondaryButton: .default(Text("Cancel")) {
                        blockingAlert = nil
                    }
                )
            } else {
                return Alert(
                    title: Text(blockingAlert!.alertMessage),
                    dismissButton: .default(Text("OK")) {
                        blockingAlert = nil
                    }
                )
            }
        }
        .overlay(
            ToastView(message: $nonBlockingMessage)
        )
        .onAppear {
            // Automatic screen view tracking in the Customer.io SDK does not work with SwiftUI apps (only UIKit apps).
            // Therefore, this is how we can perform manual screen view tracking.
            CustomerIO.shared.screen(name: "Dashboard")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
