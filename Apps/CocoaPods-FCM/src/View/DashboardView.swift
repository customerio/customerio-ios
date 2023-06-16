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

    @State private var showingDeviceAttributesSheet = false
    @State private var showingDeviceAttributesAlert = false
    @State private var deviceAttributeName: String = ""
    @State private var deviceAttributeValue: String = ""

    @State private var showingProfileAttributesSheet = false
    @State private var showingProfileAttributesAlert = false
    @State private var profileAttributeName: String = ""
    @State private var profileAttributeValue: String = ""

    @EnvironmentObject var userManager: UserManager

    @State private var showSettings: Bool = false
    @State private var showAskForPushPermissionButton = false

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

            VStack(spacing: 10) {
                if let loggedInUserEmail = userManager.email {
                    Text(loggedInUserEmail)
                }
                Text("What would you like to test?")

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
                    showingCustomEventSheet.toggle()
                }.setAppiumId("Custom Event Button")
                    .sheet(isPresented: $showingCustomEventSheet, content: {
                        VStack(spacing: 15) {
                            TextField("Event name", text: $customEventName)
                            TextField("Property name", text: $customEventPropertyName)
                            TextField("Property value", text: $customEventPropertyValue)
                            Button("Send event") {
                                CustomerIO.shared.track(name: customEventName, data: [
                                    customEventPropertyName: customEventPropertyValue
                                ])

                                showingCustomEventAlert.toggle()
                            }.alert(isPresented: $showingCustomEventAlert) {
                                Alert(
                                    title: Text("Track event sent"),
                                    dismissButton: .default(Text("OK"))
                                )
                            }
                        }.padding([.leading, .trailing], 50)
                    })
                ColorButton("Set Device Attribute") {
                    showingDeviceAttributesSheet.toggle()
                }.setAppiumId("Device Attribute Button")
                    .sheet(isPresented: $showingDeviceAttributesSheet, content: {
                        VStack(spacing: 15) {
                            TextField("Attribute name", text: $deviceAttributeName)
                            TextField("Attribute value", text: $deviceAttributeValue)
                            Button("Send device attributes") {
                                CustomerIO.shared.deviceAttributes = [
                                    deviceAttributeName: deviceAttributeValue
                                ]

                                showingDeviceAttributesAlert.toggle()
                            }.alert(isPresented: $showingDeviceAttributesAlert) {
                                Alert(
                                    title: Text("Device attribute sent"),
                                    dismissButton: .default(Text("OK"))
                                )
                            }
                        }.padding([.leading, .trailing], 50)
                    })
                ColorButton("Set Profile Attribute") {
                    showingProfileAttributesSheet.toggle()
                }.setAppiumId("Profile Attribute Button")
                    .sheet(isPresented: $showingProfileAttributesSheet, content: {
                        VStack(spacing: 15) {
                            TextField("Attribute name", text: $profileAttributeName)
                            TextField("Attribute value", text: $profileAttributeValue)
                            Button("Send profile attributes") {
                                CustomerIO.shared.profileAttributes = [
                                    profileAttributeName: profileAttributeValue
                                ]

                                showingProfileAttributesAlert.toggle()
                            }.alert(isPresented: $showingProfileAttributesAlert) {
                                Alert(
                                    title: Text("Profile attribute sent"),
                                    dismissButton: .default(Text("OK"))
                                )
                            }
                        }.padding([.leading, .trailing], 50)
                    })
                if showAskForPushPermissionButton {
                    ColorButton("Show Push Prompt") {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                            if granted {
                                DispatchQueue.main.async {
                                    UIApplication.shared.registerForRemoteNotifications()
                                }
                            }
                        }

                        showAskForPushPermissionButton = false
                    }.setAppiumId("Show Push Prompt Button")
                }
                ColorButton("Logout") {
                    CustomerIO.shared.clearIdentify()

                    userManager.logout()
                }.setAppiumId("Log Out Button")
                EnvironmentText()
            }
            .padding()
        }.onAppear {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                showAskForPushPermissionButton = settings.authorizationStatus == .notDetermined
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
