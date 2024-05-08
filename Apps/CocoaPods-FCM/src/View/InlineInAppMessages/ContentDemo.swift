//
//  ContentDemo.swift
//  test cocoapods
//
//  Created by Ahmed Ali on 09/05/2024.
//

import SwiftUI
import CioMessagingInApp

struct ContentDemo: View {
    @Binding var navPath: [NavScreen]
    var body: some View {
        VStack {
            HStack {
                InlineMessageView(elementId: "ios-back") { _ in
                    _ = navPath.popLast()
                }
                .frame(width: 80)
                Spacer()
            }
            
            Text(
            """
            What you are seeing so far is a blend between iOS native components and Customer.io's inline messages.
            """
            )
            
            InlineMessageView(elementId: "ios-content")
            Spacer()
        }
        .padding(.leading, 16)
        .navigationBarBackButtonHidden()
    }
}

#Preview {
    ContentDemo(navPath: .constant([]))
}
