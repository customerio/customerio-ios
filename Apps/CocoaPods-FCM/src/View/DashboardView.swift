import CioDataPipelines
import CioMessagingInApp
import SwiftUI
import UIKit
import UserNotifications

struct InAppMessageViewRepresentable: UIViewRepresentable {
    var elementId: String
    @Binding var containerWidth: CGFloat
    func makeUIView(context: Context) -> UIView {
        let inlineMessageView = InAppMessageView(elementId: elementId)
        inlineMessageView.onActionDelegate = context.coordinator
//                inlineMessageView.translatesAutoresizingMaskIntoConstraints = false

        let widthConstraint = inlineMessageView.widthAnchor.constraint(equalToConstant: containerWidth)
        widthConstraint.isActive = true
        widthConstraint.isActive = true
        inlineMessageView.backgroundColor = UIColor.darkGray
        //        inlineMessageView.widthAnchor.constraint(equalTo: View.widthAnchor).isActive = true

        //        addSubview(inlineMessageView)
        //        return inlineMessageView

        let view = UIView()
        let label = UILabel()
        label.text = "This is a UILabel from UIKit"
        label.textColor = .black
        view.backgroundColor = UIColor.green
        view.addSubview(inlineMessageView)
        inlineMessageView.translatesAutoresizingMaskIntoConstraints = false
        inlineMessageView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
//        NSLayoutConstraint.activate([
//            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
//        ])
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let widthConstraint = uiView.constraints.first(where: { $0.firstAttribute == .width }) {
            widthConstraint.constant = containerWidth
        }
    }

    // Add a coordinator to handle delegate `InAppMessageViewActionDelegate`
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, InAppMessageViewActionDelegate {
        var parent: InAppMessageViewRepresentable

        init(_ parent: InAppMessageViewRepresentable) {
            self.parent = parent
        }

        func onActionClick(message: InAppMessage, actionValue: String, actionName: String) {
            print("This method received a callback on button click")
        }
    }
}

struct DashboardView: View {
    @State private var containerWidth: CGFloat = 0
    @State private var inAppMessageHeight: CGFloat = 0

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
//        ScrollView {
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
                    InAppMessageViewRepresentable(elementId: "dashboard-announcement", containerWidth: $containerWidth)
                        .background(GeometryReader { _ in
                            Color.clear.onAppear {
                                //                                containerWidth = geometry.size.width
                            }
                        })
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
            }
            .padding()
        }
//        }
        .setBackgroundColor(.orange)
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
