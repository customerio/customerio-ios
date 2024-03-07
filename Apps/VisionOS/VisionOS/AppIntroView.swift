import MarkdownUI
import SwiftUI

struct SampleAppIntro: View {
    static let title = ScreenTitleConfig(
        "Welcome to **Customer.io** *&*",
        menuTitle: "App Intro",
        showVisionProLogo: true
    )

    @ObservedObject var state = AppState.shared

    var body: some View {
        Markdown {
            """
            We're excited to have you onboard as we explore the walk through the capabilities of
            **Customer.io** within the realm of spacial computing generally and VisionPro specifically.

            This sample app is more than just a demonstration—it's a hands-on guide
            designed to familiarize you with **Customer.io Swift SDK**. You'll learn not only how to integrate the SDK into your VisionPro app but also how
            it contributes to leveraging **Customer.io**'s marketing prowess to enhance the user engagement.

            **P.S.:** For those eager to jump straight into the code,
            the `MainScreen.swift` file in the sample app provides a quick overview of the `CustomerIO` class in action.

            Ready to embark on this immersive journey? Let's start by
            [installing CustomerIO SDK](\(InlineNavigationLink.install))
            """
        }
        .onAppear {
            state.titleConfig = Self.title
            state.visitedLinks.insert(.sampleAppIntro)
        }
    }
}

#Preview {
    CommonLayoutView {
        SampleAppIntro()
    }
}
