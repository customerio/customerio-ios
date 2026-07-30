import ActivityKit
import CioDataPipelines
import CioInternalCommon
import CioLiveActivities
import CioLiveActivities_Attributes
import CioLiveActivities_Templates
import CioMessagingInbox
import SwiftUI
import UserNotifications

struct DashboardView: View {
    enum Subscreen: String {
        case customEvent
        case profileAttribute
        case deviceAttribute
        case settings
    }

    struct BlockingAlert: Identifiable {
        var id: String { alertMessage }
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

    func requestSettings() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
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
                let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                if granted ?? false {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            default: break
            }
        }
    }

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
                                properties: [
                                    "movie_name": "The Incredibles"
                                ]
                            )
                        default: // case 2
                            CustomerIO.shared.track(
                                name: "appointmentScheduled",
                                properties: [
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

                    if #available(iOS 16.2, *) {
                        ColorButton("Start Live Activity") {
                            startSegmentsLiveActivity()
                        }.setAppiumId("Start Live Activity Button")
                        ColorButton("End Live Activity") {
                            endSegmentsLiveActivity()
                        }.setAppiumId("End Live Activity Button")
                    }

                    ColorButton("Show Push Prompt") {
                        requestSettings()
                    }.setAppiumId("Show Push Prompt Button")
                    ColorButton("Logout") {
                        CustomerIO.shared.clearIdentify()

                        userManager.logout()
                    }.setAppiumId("Log Out Button")
                }

                EnvironmentText()
            }
            .padding()

            // Drop-in Visual Notification Inbox overlay: floating bell (shown only when the data
            // layer reports the inbox visible) that opens the Jist-rendered list in a bottom sheet.
            // Mounted last so it overlays the dashboard. iOS 16+ (the overlay uses system detents).
            if #available(iOS 16, *) {
                NotificationInboxOverlay()
            }
        }
        // Can only use 1 alert() in a View so we combine the different types of Alerts into 1 function.
        .alert(item: $blockingAlert) { alert in
            if let alertCallToAction = blockingAlert!.callToActionButton {
                return Alert(
                    title: Text(alert.alertMessage),
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
            CustomerIO.shared.screen(title: "Dashboard")
        }
    }
}

// MARK: - Live Activities

@available(iOS 16.2, *)
private extension DashboardView {
    /// Starts the SDK's Segments template. Rendering comes from the `LiveActivityWidget` extension,
    /// which links only the Attributes + Templates pods — this app writes no widget UI of its own.
    func startSegmentsLiveActivity() {
        do {
            try CustomerIO.liveActivities.start(
                CIOSegmentsAttributes(header: "CocoaPods FCM"),
                contentState: .init(
                    status: "Order placed",
                    substatus: "We got your order",
                    segmentsTotal: 4,
                    segmentsComplete: 1,
                    trailingText: "1/4",
                    cioMetadata: CIOLiveActivityMetadata(deepLink: "cocoapods-fcm://dashboard")
                )
            )
        } catch {
            print("Live Activity start failed: \(error)")
        }
    }

    /// Ends whichever Segments activity is running. Looks it up through ActivityKit and `adopt`s it
    /// rather than holding a handle — what a real app does after a relaunch.
    func endSegmentsLiveActivity() {
        Task {
            for activity in Activity<CIOSegmentsAttributes>.activities {
                guard let handle = CustomerIO.liveActivities.adopt(activity) else {
                    print("Live Activity adopt returned nil for \(activity.id)")
                    continue
                }
                await handle.end(.init(
                    status: "Delivered",
                    substatus: "Enjoy!",
                    segmentsTotal: 4,
                    segmentsComplete: 4,
                    trailingText: "4/4"
                ))
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
