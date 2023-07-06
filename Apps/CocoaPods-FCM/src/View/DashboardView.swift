import CioTracking
import SwiftUI
import UserNotifications

struct DashboardView: View {
    @State private var showRandomEventSentAlert = false

    @State private var showingCustomEventSheet = false
    @State private var showingCustomEventAlert = false
    @State private var customEventName: String = ""
    @State private var customEventPropertyName: String = ""
    @State private var customEventPropertyValue: String = ""

    @EnvironmentObject var userManager: UserManager

    @State private var showSettings: Bool = false

    @State private var navigateToCustomEventScreen = false
    @State private var navigateToProfileAttributesScreen = false
    @State private var navigateToDeviceAttributesScreen = false

    @State private var pushPromptAlertMessage: String?

    var body: some View {
        ZStack {
            VStack {
                SettingsButton {
                    showSettings = true
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 10)
                Spacer()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView {
                    showSettings = false
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

                        showRandomEventSentAlert.toggle()
                    }
                    .setAppiumId("Random Event Button")
                    .alert(isPresented: $showRandomEventSentAlert) {
                        Alert(
                            title: Text("Random event sent"),
                            dismissButton: .default(Text("OK"))
                        )
                    }

                    ColorButton("Send Custom Event") {
                        navigateToCustomEventScreen = true
                    }.setAppiumId("Custom Event Button")
                        .sheet(isPresented: $navigateToCustomEventScreen) {
                            CustomEventView(close: {
                                navigateToCustomEventScreen = false
                            }, done: { eventName, propertyName, propertyValue in
                                CustomerIO.shared.track(name: eventName, data: [
                                    propertyName: propertyValue
                                ])

                                navigateToCustomEventScreen = false
                            })
                        }

                    ColorButton("Set Device Attribute") {
                        navigateToDeviceAttributesScreen = true
                    }.setAppiumId("Device Attribute Button")
                        .sheet(isPresented: $navigateToDeviceAttributesScreen) {
                            CustomAttributeView(attributeType: .deviceAttributes, close: {
                                navigateToDeviceAttributesScreen = false
                            }, done: { name, value in
                                CustomerIO.shared.deviceAttributes = [name: value]

                                navigateToDeviceAttributesScreen = false
                            })
                        }

                    ColorButton("Set Profile Attribute") {
                        navigateToProfileAttributesScreen = true
                    }.setAppiumId("Profile Attribute Button")
                        .sheet(isPresented: $navigateToProfileAttributesScreen) {
                            CustomAttributeView(attributeType: .profileAttributes, close: {
                                navigateToProfileAttributesScreen = false
                            }, done: { name, value in
                                CustomerIO.shared.profileAttributes = [name: value]

                                navigateToProfileAttributesScreen = false
                            })
                        }

                    ColorButton("Show Push Prompt") {
                        UNUserNotificationCenter.current().getNotificationSettings { settings in
                            switch settings.authorizationStatus {
                            case .authorized:
                                pushPromptAlertMessage = "Push permission already granted"
                            case .denied:
                                pushPromptAlertMessage = "Push permission denied. You will need to go into the Settings app to change the push permission for this app."
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
                        .alert(isPresented: .notNil(pushPromptAlertMessage)) {
                            Alert(
                                title: Text("Push"),
                                message: Text(pushPromptAlertMessage!),
                                dismissButton: .default(Text("OK"))
                            )
                        }
                    ColorButton("Logout") {
                        CustomerIO.shared.clearIdentify()

                        userManager.logout()
                    }.setAppiumId("Log Out Button")
                }

                EnvironmentText()
            }
            .padding()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
