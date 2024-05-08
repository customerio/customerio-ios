//
//  TopBannerDemo.swift
//  test cocoapods
//
//  Created by Ahmed Ali on 09/05/2024.
//

import SwiftUI
import CioMessagingInApp

struct TopBannerDemo: View {
    var body: some View {
        VStack {
            InlineMessageView(elementId: "ios-banner")
            Divider()
            Rectangle()
                .foregroundColor(.blue)
                .overlay {
                    Text("Text Content")
                        .foregroundStyle(.white)
                }
                .frame(height: 100)
            InlineMessageView(elementId: "ios-buttons")
            Rectangle()
                .foregroundColor(.green)
                .overlay {
                    HStack {
                        NativeButton(text: "Button One", bgColor: .blue, textColor: .white)
                        Spacer()
                        NativeButton(text: "Button Two", bgColor: .white, textColor: .black)
                    }
                    .padding(.horizontal, 32)
                    
                }
                .frame(height: 100)
            
            
            Spacer()
        }
        
    }
}

struct NativeButton: View {
    let text: String
    let bgColor: Color
    let textColor: Color
    
    var body: some View {
        Button {
                
            } label: {
                Text(text)
                    .padding()
                    .foregroundColor(textColor)
                    .background(
                        RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                        .fill(bgColor)
                    )
                    .fontWeight(.bold)
            }
    }
}

#Preview {
    TopBannerDemo()
}
