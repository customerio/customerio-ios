import CioTracking
import SwiftUI

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

    var body: some View {
        VStack(spacing: 40) {
            Text("What would you like to test?")

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
            }
            Text("SDK: \(EnvironmentUtil.cioSdkVersion) \n app: \(EnvironmentUtil.appBuildVersion) (\(EnvironmentUtil.appBuildNumber))")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
