import CioDataPipelines
import CioMessagingInApp
import SwiftUI
import UIKit
import UserNotifications

// ObservableObject that tracks the height of a subview
class HeightTracker: ObservableObject {
    @Published var subviewHeight: CGFloat = 0
}

// Used for associating the height tracker with InAppMessageView
private var heightTrackerKey: UInt8 = 0
private var maxHeight: CGFloat = 0

extension InAppMessageView {
    var heightTracker: HeightTracker? {
        get {
            objc_getAssociatedObject(self, &heightTrackerKey) as? HeightTracker
        }
        set {
            objc_setAssociatedObject(self, &heightTrackerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    // Tracks and update the height
    override public func layoutSubviews() {
        super.layoutSubviews()

        print("Height of tracker \(String(describing: heightTracker?.subviewHeight))")

        // Update maxHeight and notify heightTracker if the frame height changes
        // The height fluctuates, increasing and then decreasing.
        // To prevent this behavior, we constrain it to the maximum height achieved by the subview.
        if frame.height >= maxHeight {
            maxHeight = frame.height
            heightTracker?.subviewHeight = frame.height
        }
    }
}

struct InAppMessageViewRepresentable: UIViewRepresentable {
    var elementId: String
    @Binding var containerWidth: CGFloat
    @ObservedObject var heightTracker: HeightTracker
    func makeUIView(context: Context) -> InAppMessageView {
        let inlineMessageView = InAppMessageView(elementId: elementId)

        // This is optional. If set, the delegate method `onActionClick`
        // will receive callbacks.
        // If not set, the global method `messageActionTaken` will handle the callbacks.
        inlineMessageView.onActionDelegate = context.coordinator
        inlineMessageView.translatesAutoresizingMaskIntoConstraints = false
        inlineMessageView.heightTracker = heightTracker

        // Add a width constraint based on the containerWidth
        let widthConstraint = inlineMessageView.widthAnchor.constraint(equalToConstant: containerWidth)
        widthConstraint.isActive = true
        return inlineMessageView
    }

    func updateUIView(_ uiView: InAppMessageView, context: Context) {
        // Update the width constraint if it exists
        if let widthConstraint = uiView.constraints.first(where: { $0.firstAttribute == .width }) {
            widthConstraint.constant = containerWidth
        }
        // Update the height constraint if it exists
        if let heightConstraint = uiView.constraints.first(where: { $0.firstAttribute == .height }) {
            heightConstraint.constant = heightTracker.subviewHeight
        }
    }

    // Coordinator to handle delegate `InAppMessageViewActionDelegate`
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, InAppMessageViewActionDelegate {
        var parent: InAppMessageViewRepresentable

        init(_ parent: InAppMessageViewRepresentable) {
            self.parent = parent
        }

        // Delegate method for handling custom button action clicks
        func onActionClick(message: InAppMessage, actionValue: String, actionName: String) {
            print("You can perform any action here. For instance, we are tracking the custom button tap.")
            CustomerIO.shared.track(name: "inline custom button action", properties: [
                "delivery-id": message.deliveryId ?? "(none)",
                "message-id": message.messageId,
                "action-value": actionValue,
                "action-name": actionName
            ])
        }
    }
}

struct DashboardView: View {
    @State private var containerWidth: CGFloat = 0
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
    @StateObject private var heightTracker = HeightTracker()
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

            ScrollView {
                VStack(spacing: 15) {
                    if let loggedInUserEmail = userManager.email {
                        Text(loggedInUserEmail)
                    }
                    Text("What would you like to test?")
                    Group {
                        // ---- In-app Inline View ----
                        InAppMessageViewRepresentable(elementId: "dashboard-announcement", containerWidth: $containerWidth, heightTracker: heightTracker)
                            // Set the height of the view based on the height tracked
                            .frame(height: heightTracker.subviewHeight)
                            // GeometryReader to track the size of the container
                            .background(GeometryReader { geometry in
                                Color.clear.onAppear {
                                    containerWidth = geometry.size.width
                                }
                            })
                        // ---- In-app Inline View ----
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
            CustomerIO.shared.screen(title: "Dashboard")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
