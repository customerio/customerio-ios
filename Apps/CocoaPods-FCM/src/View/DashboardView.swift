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

    @State private var nonBlockingMessage: String?
    @State private var blockingMessage: String?

    @State private var subscreenShown: Subscreen?

    @State private var customEventName: String = ""
    @State private var customEventPropertyName: String = ""
    @State private var customEventPropertyValue: String = ""

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
                        .sheet(isPresented: .constant(subscreenShown == .customEvent)) {
                            CustomEventView(close: {
                                subscreenShown = nil
                            })
                        }

                    ColorButton("Set Device Attribute") {
                        subscreenShown = .deviceAttribute
                    }.setAppiumId("Device Attribute Button")
                        .sheet(isPresented: .constant(subscreenShown == .deviceAttribute)) {
                            CustomAttributeView(attributeType: .device, close: {
                                subscreenShown = nil
                            })
                        }

                    ColorButton("Set Profile Attribute") {
                        subscreenShown = .profileAttribute
                    }.setAppiumId("Profile Attribute Button")
                        .sheet(isPresented: .constant(subscreenShown == .profileAttribute)) {
                            CustomAttributeView(attributeType: .profile, close: {
                                subscreenShown = nil
                            })
                        }

                    ColorButton("Show Push Prompt") {
                        UNUserNotificationCenter.current().getNotificationSettings { settings in
                            switch settings.authorizationStatus {
                            case .authorized:
                                blockingMessage = "Push permission already granted"
                            case .denied:
                                blockingMessage = "Push permission denied. You will need to go into the Settings app to change the push permission for this app."
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
            .alert(isPresented: .notNil(blockingMessage)) {
                Alert(
                    title: Text(blockingMessage!),
                    dismissButton: .default(Text("OK")) {
                        blockingMessage = nil
                    }
                )
            }
        }.overlay(
            ToastView(message: $nonBlockingMessage)
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
