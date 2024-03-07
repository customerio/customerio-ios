import MarkdownUI
import SwiftUI

struct PostInitializeCustomerIOIntro: View {
    @ObservedObject var state = AppState.shared

    static let title = ScreenTitleConfig("Customer.io In a Nutshell")
    var body: some View {
        ScrollView(.vertical) {
            Markdown {
"""
Congratulations! Now you integrated the SDK. Before we
use it, let's do a very simplified version of what **Customer.io**
platform is about, from the lense of a VisionOS or iOS developer and
how you can unlock the platform capabilities for your marketing team.

Beside other things, **Customer.io** serves as a message automation platform which can be used to help marketers reach their audience through targetted campaigns and the needed analysis for these campaigns to understand the strategies that leads to successful conversaions.

In order to achieve that, companies use the client SDKs like this one to enrich Customer.io with the data needed to enable the marketing team to build such campaigns and analysis.


The following photo describes how the flow of data usually looks like
"""
            }
            Image("PostInitialize")
                .resizable()

            Markdown {
                """

                From the client side, the first you need to do is to
                [Identify](\(InlineNavigationLink.identify)) the user.
                Then you can do things like:
                """

                if state.profile.loggedIn {
                    """
                    - [Add/Set profile attributes](\(InlineNavigationLink.profileAttributes)).
                    i.e their job title, hobbies, etc...
                    - [Track events](\(InlineNavigationLink.track)). For example when user visit specific screen in the app, or tap a button.
                    - [Add/Set device attributes](\(InlineNavigationLink.deviceAttributes)).
                    Other compaigns might want to only target user with specific
                    device capabilities or screen sizes, etc.
                    """
                } else {
                    """
                    - Add/Set profile attributes.
                    i.e their job title, hobbies, etc...
                    - Track events. For example when user visit specific screen in the app,
                    or tap a button.
                    - Add/Set device attributes. Other compaigns might want to only target
                    user with specific device capabilities or screen sizes, etc.
                    """
                }

                """
                As you can tell by now, it is these information you report to
                **Customer.io** that makes the magic happen. It also mean, sometime if
                you decide to change an event name, or a profile attribute, it might
                impact running compaigns that use these names on **Customer.io**.

                Now we are ready to start [Identify](\(InlineNavigationLink.identify))ing.

                *P.s if you want to know more about how the difference pieces connect together
                checkout the
                [Journeys Introduction](https://customer.io/docs/journeys/journeys-overview/)*

                """
            }
        }
        .onAppear {
            state.titleConfig = Self.title
        }
    }
}

#Preview {
    CommonLayoutView {
        PostInitializeCustomerIOIntro()
    }
}
