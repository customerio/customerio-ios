//
//  InlineGistSwiftUIView.swift
//  CustomerIOMessagingInApp
//
//  Created by Ahmed Ali on 09/05/2024.
//

import SwiftUI

final class GistViewWrapper: UIViewRepresentable, GistViewDelegate {
    let gistView: GistView
    
    private var gistViewWidth: CGFloat?
    private var gistViewHeight: CGFloat?
    private var proposedWidth: CGFloat?
    
    init(_ gistView: GistView) {
        self.gistView = gistView
        self.gistView.delegate = self
    }
    
    
    func makeUIView(context: Context) -> UIView {
        self.gistView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        
    }
    
    @available(iOS 16, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        nil
    }
    
    func action(message: Message, currentRoute: String, action: String, name: String) {
        
    }
    
    func sizeChanged(message: Message, width: CGFloat, height: CGFloat) {
        
    }
    
}

public struct InlineGistSwiftView: View {
    let gistView: GistView
    
    public var body: some View {
        GistViewWrapper(gistView)
    }
}

#Preview {
    InlineGistSwiftView(gistView:GistView())
}
