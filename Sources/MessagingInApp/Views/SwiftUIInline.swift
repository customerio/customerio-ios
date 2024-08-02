import Foundation
#if canImport(SwiftUI)
import SwiftUI

public struct InAppMessageViewRepresentable: UIViewRepresentable {
    public var elementId: String
    public var onActionClick: ((InAppMessage, String, String) -> Void)?

    public init(elementId: String, onActionClick: ((InAppMessage, String, String) -> Void)? = nil) {
        self.elementId = elementId
        self.onActionClick = onActionClick
    }

    public func makeUIView(context: Context) -> InAppMessageView {
        let inlineMessageView = InAppMessageView(elementId: elementId)
        // This is optional. If set, the delegate method `onActionClick`
        // will receive callbacks.
        // If not set, the global method `messageActionTaken` will handle the callbacks.
        if let _ = onActionClick {
            inlineMessageView.onActionDelegate = context.coordinator
        }
        return inlineMessageView
    }

    public func updateUIView(_ uiView: InAppMessageView, context: Context) {
        // Update your view here if needed
    }

//     Coordinator to handle delegate `InAppMessageViewActionDelegate`
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, InAppMessageViewActionDelegate {
        var parent: InAppMessageViewRepresentable

        init(_ parent: InAppMessageViewRepresentable) {
            self.parent = parent
        }

        // Delegate method for handling custom button action clicks
        public func onActionClick(message: InAppMessage, actionValue: String, actionName: String) {
            parent.onActionClick?(message, actionValue, actionName)
        }
    }
}
#endif
