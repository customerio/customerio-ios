import Foundation
#if canImport(SwiftUI)
import SwiftUI

/**
 A SwiftUI view that displays an inline in-app message.

 A SwiftUI wrapper around inline in-app message View that provides some of the features of inline in-app messaging feature:
 * Animate height changes when in-app messages render.
 * Dismiss the message when close button pressed.
 * Show loading indicators when loading new messages.

 */
public struct InlineInAppMessage: View {
    let elementId: String
    let onActionClick: ((InAppMessage, String, String) -> Void)?

    @State private var height: CGFloat = 0

    public init(elementId: String, onActionClick: ((InAppMessage, String, String) -> Void)? = nil) {
        self.elementId = elementId
        self.onActionClick = onActionClick
    }

    public var body: some View {
        // Create a parent wrapper around the UIKit view so we can animate height changes and close the in-app message.
        // The UIKit View has an intrinstic size that we cannot manipulate directly. Instead, by wrapping the UIKit View, we have control over the visibility of the child UIKit View.
        VStack {
            InAppMessageViewRepresentable(elementId: elementId, onActionClick: onActionClick, onHeightChange: { newHeight in
                withAnimation(.easeIn(duration: 0.3)) {
                    height = newHeight
                }
            })
        }.frame(height: height)
    }
}

// UIViewRepresentable to wrap the UIKit in-app message View. Required to use UIKit views in SwiftUI.
// Mostly used to send events between the two frameworks: SwiftUI <--> UIKit.
public struct InAppMessageViewRepresentable: UIViewRepresentable {
    public var elementId: String
    public var onActionClick: ((InAppMessage, String, String) -> Void)?
    public var onHeightChange: (CGFloat) -> Void

    public init(elementId: String, onActionClick: ((InAppMessage, String, String) -> Void)?, onHeightChange: @escaping ((CGFloat) -> Void)) {
        self.elementId = elementId
        self.onActionClick = onActionClick
        self.onHeightChange = onHeightChange
    }

    public func makeUIView(context: Context) -> InAppMessageView {
        let inlineMessageView = InAppMessageView(elementId: elementId)

        inlineMessageView.onActionDelegate = context.coordinator
        inlineMessageView.onSizeChangedDelegate = context.coordinator

        return inlineMessageView
    }

    public func updateUIView(_ uiView: InAppMessageView, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, InAppMessageViewActionDelegate, InAppMessageViewSizeChangedDelegate {
        var parent: InAppMessageViewRepresentable

        init(_ parent: InAppMessageViewRepresentable) {
            self.parent = parent
        }

        public func onActionClick(message: InAppMessage, actionValue: String, actionName: String) {
            parent.onActionClick?(message, actionValue, actionName)
        }

        public func onSizeChanged(height: CGFloat, width: CGFloat) {
            parent.onHeightChange(height)
        }
    }
}
#endif
