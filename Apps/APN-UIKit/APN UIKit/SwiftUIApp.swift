//
//  SwiftUIApp.swift
//  APN UIKit
//
//  Created by Uros Milivojevic on 9.4.25..
//

import SwiftUI
import CioDataPipelines
import CioMessagingInApp
import CioMessagingPushAPN

@available(iOS 14.0, *)
//@main
struct CioSwiftUIApp: App {
    @UIApplicationDelegateAdaptor(CioAppDelegate.self) private var appDelegate
//    @UIApplicationDelegateAdaptor(CioAppDelegateWrapper<AppDelegate>.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}


struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Customer.io Demo")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            .padding()
        }
    }
}
