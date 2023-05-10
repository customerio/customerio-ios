import CioTracking
import SwiftUI
import UserNotifications

struct DashboardView: View {
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

    @State private var openedDeepLinkUrl: URL?
    @State private var showOpenedDeepLink: Bool = false // I would like for this value to be set based on openedDeepLinkUrl != nil but can't figure that out yet.

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
                Text("What would you like to test?")

                if showAskForPushPermissionButton {
                    ColorButton(title: "Ask for push permission") {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                            if granted {
                                DispatchQueue.main.async {
                                    UIApplication.shared.registerForRemoteNotifications()
                                }
                            }
                        }

                        showAskForPushPermissionButton = false
                    }
                }
                ColorButton(title: "Send Random Event") {
                    CustomerIO.shared.track(
                        name: String.random,
                        data: [
                            "randomAttribute": String.random,
                            "random_attribute": String.random
                        ]
                    )
                }
                ColorButton(title: "Send Custom Event") {
                    showingCustomEventSheet.toggle()
                }.sheet(isPresented: $showingCustomEventSheet, content: {
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
                ColorButton(title: "Set Device Attributes") {
                    showingDeviceAttributesSheet.toggle()
                }.sheet(isPresented: $showingDeviceAttributesSheet, content: {
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
                ColorButton(title: "Set Profile Attributes") {
                    showingProfileAttributesSheet.toggle()
                }.sheet(isPresented: $showingProfileAttributesSheet, content: {
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
                ColorButton(title: "Logout") {
                    CustomerIO.shared.clearIdentify()

                    userManager.logout()
                }
                EnvironmentText()
            }
            .padding()
        }.onAppear {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                showAskForPushPermissionButton = settings.authorizationStatus == .notDetermined
            }
            // App opens via Universal Link.
            // Any URL that begins with `https://ciosample.page.link` will open this app and display the URL to you in a pop-up.
        }.onOpenURL { deepLink in
            openedDeepLinkUrl = deepLink
            showOpenedDeepLink = true
        }.alert(isPresented: $showOpenedDeepLink) {
            Alert(
                title: Text("Deep link opened!"),
                message: Text(openedDeepLinkUrl!.absoluteString),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
