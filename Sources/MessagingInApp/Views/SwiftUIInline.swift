import Foundation
#if canImport(SwiftUI)
import SwiftUI

/**
 A SwiftUI view that displays an inline in-app message.

 A SwiftUI wrapper around inline in-app message View that provides some of the features of inline in-app messaging feature:
 * Animate height changes when in-app messages render.
 * Dismiss the message when close button pressed.
 * Show loading indicators when loading new messages.

 This is the public View that customers use in their SwiftUI app.
 */
public struct InlineMessage: View {
    let elementId: String
    let onActionClick: ((InAppMessage, String, String) -> Void)?

    @State private var height: CGFloat = 0
    @State private var isChangingMessages = false

    public init(elementId: String, onActionClick: ((InAppMessage, String, String) -> Void)? = nil) {
        self.elementId = elementId
        self.onActionClick = onActionClick
    }

    public var body: some View {
        // Create a parent wrapper around the UIKit view so we can animate height changes and close the in-app message.
        // The UIKit View has an intrinstic size that we cannot manipulate directly. Instead, by wrapping the UIKit View, we have control over the visibility of the child UIKit View.

        // The ZStack is used to overlay the loading indicator on top of the in-app message view.
        ZStack {
            InlineMessageUIViewRepresentable(elementId: elementId, onActionClick: onActionClick, onHeightChange: { newHeight in
                isChangingMessages = false // if the loading view is currently being shown, hide it.

                withAnimation(.easeIn(duration: 0.3)) {
                    height = newHeight
                }
            }, willChangeMessage: { _, onComplete in
                isChangingMessages = true // show loading view to indicate to the user that a new message is loading.
                onComplete()
            })
            // Hide this view when the loading view is shown. This is so the background color of the loading View is the background color of the customer's screen.
            // Do not use `if ... { InAppMessageView }` to show/hide the UIView because I have found that this method makes the Gist webview events no longer trigger, breaking the feature.
            .opacity(isChangingMessages ? 0 : 1)

            // Show a loading indicator when a new message is being fetched.
            // Because we are using ZStack, this View will be displayed over the InAppMessageView.
            if isChangingMessages {
                ActivityIndicator()
            }
        }.frame(height: height) // By setting height on the parent container, we can dismiss a message by setting height to 0.
    }
}

// UIViewRepresentable to wrap the UIKit in-app message View. Required to use UIKit views in SwiftUI.
// Mostly used to send events between the two frameworks: SwiftUI <--> UIKit.
public struct InlineMessageUIViewRepresentable: UIViewRepresentable {
    public var elementId: String
    public var onActionClick: ((InAppMessage, String, String) -> Void)?
    public var onHeightChange: (CGFloat) -> Void
    public var willChangeMessage: ((newTemplateId: String, onComplete: () -> Void)) -> Void

    public init(elementId: String, onActionClick: ((InAppMessage, String, String) -> Void)?, onHeightChange: @escaping ((CGFloat) -> Void), willChangeMessage: @escaping ((newTemplateId: String, onComplete: () -> Void)) -> Void) {
        self.elementId = elementId
        self.onActionClick = onActionClick
        self.onHeightChange = onHeightChange
        self.willChangeMessage = willChangeMessage
    }

    public func makeUIView(context: Context) -> GistInlineMessageUIView {
        let inlineMessageView = GistInlineMessageUIView(elementId: elementId)

        inlineMessageView.delegate = context.coordinator

        return inlineMessageView
    }

    public func updateUIView(_ uiView: GistInlineMessageUIView, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, GistInlineMessageUIViewDelegate {
        var parent: InlineMessageUIViewRepresentable

        init(_ parent: InlineMessageUIViewRepresentable) {
            self.parent = parent
        }

        public func onMessageRendered(width: CGFloat, height: CGFloat) {
            parent.onHeightChange(height)
        }

        public func onNoMessageToDisplay() {
            parent.onHeightChange(0)
        }

        public func onInlineButtonAction(message: Message, currentRoute: String, action: String, name: String) -> Bool {
            guard let parent = parent.onActionClick else { return false }

            parent(InAppMessage(gistMessage: message), action, name)

            return true
        }

        public func willChangeMessage(newTemplateId: String, onComplete: @escaping () -> Void) {
            parent.willChangeMessage((newTemplateId: newTemplateId, onComplete: onComplete))
        }
    }
}

// UIActivityIndicatorView to use in SwiftUI.
// Must use this because SwiftUI activity indicator was introduced in iOS 14.
struct ActivityIndicator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.startAnimating()
        return indicator
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {}
}

#endif
