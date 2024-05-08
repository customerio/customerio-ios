import Foundation
import SwiftUI


struct InlineMessageViewWrapper: UIViewRepresentable {
    let uiView: UIView?

    func makeUIView(context: Context) -> UIView {
        uiView ?? UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        
    }

}


struct InlineMessageViewContainer: View {
    let content: InlineMessageViewWrapper
    let width: CGFloat?
    let height: CGFloat?
    
    public var body: some View {
        if let width, let height {
            content
                .frame(width: width, height: height)
        } else {
            content
        }
    }
}

public struct InlineMessageView: View {
    public let elementId: String
    
    @ObservedObject private var observer: InlineMessageViewObserver
    
    public init(elementId: String, onAction: ((String) -> ())? = nil) {
        self.elementId = elementId
        self.observer = InlineMessagesFactory.instance.observerView(withElementId: elementId, onAction: onAction)
    }
    
    public var body: some View {
        if observer.hasView {
            observer.view
        } else {
            EmptyView()
        }
    }
}

class InlineMessageViewObserver: ObservableObject {
    
    @Published private(set) var view: InlineMessageViewContainer = .init(content: InlineMessageViewWrapper(uiView: nil), width: nil, height: nil)
    @Published private(set) var hasView: Bool = false
    
    let onAction: ((String) -> ())?
    
    init(onAction: ((String) -> Void)?) {
        self.onAction = onAction
    }
    
    var gistView: GistView? {
        didSet {
            hasView = gistView != nil
            view = .init(content: InlineMessageViewWrapper(uiView: gistView), width: nil, height: nil)
            gistView?.delegate = self
        }
    }
}

extension InlineMessageViewObserver: GistViewDelegate {
    public func action(message: Message, currentRoute: String, action: String, name: String) {
        onAction?(action)
        print("Got an action for you!")
    }
    
    public func sizeChanged(message: Message, width: CGFloat, height: CGFloat) {
        
        print("Sizing: gist view sizeChanged: \(width), \(height)")
        if width > 0 && height > 0 && view.height != height && view.width != width {
            view = InlineMessageViewContainer(content: InlineMessageViewWrapper(uiView: gistView), width: width, height: height)
        }
    }
}

protocol InlineMessagesListener: AnyObject {
    func onDidLoadInlineMessage(withElementId: String, view: GistView)
}

@MainActor
final class InlineMessagesFactory: InlineMessagesListener {
    nonisolated static let instance = InlineMessagesFactory()
    
    private var inlineMessageWatchers: [String: InlineMessageViewObserver] = [:]
    
    nonisolated private init() {}
    
    func observerView(withElementId id: String, onAction: ((String) -> ())?) -> InlineMessageViewObserver {
        let watcher = inlineMessageWatchers[id] ?? InlineMessageViewObserver(onAction: onAction)
        watcher.gistView = Gist.shared.getMessageView(id)
        inlineMessageWatchers[id] = watcher
        return watcher
    }
    
    
    nonisolated func onDidLoadInlineMessage(withElementId id: String, view: GistView) {
        Task {
            await MainActor.run {
                if let watcher = self.inlineMessageWatchers[id] {
                    watcher.gistView = view
                }
            }
        }
    }
}
