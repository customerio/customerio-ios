import MarkdownUI
import SwiftUI

struct HowToTestIdentifyTutorialView: View {
    static let title = ScreenTitleConfig("How to Test Identify")

    @EnvironmentObject private var viewModel: ViewModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading) {
                Markdown {
"""
You can follow the steps below to verify whether your setup and
your use of `CustomerIO.shared.identify` works as expected.

Assuming you called identify with an identifier + an email.

1. Go to your
[workplace dashboard](https://fly.customer.io/workspaces/dashboard)
2. Click on the People tab in the side menu
3. Search by email or identifier
"""
                }
                Image("FindPeople")

                Markdown {
"""
After your user is identified, you can still
[add/update their profile attributes](\(InlineNavigationLink.profileAttributes))


**Note:** How quick your data will show in Customer.io depends on
the configurations you use when calling `CustomerIO.initialize`.
Learn more about these configs
[here](https://customer.io/docs/sdk/ios/getting-started/#configuration-options)
"""
                }
            }
        }
        .onAppear {
            viewModel.titleConfig = Self.title
        }
    }
}

#Preview {
    CommonLayoutView {
        HowToTestIdentifyTutorialView()
    }
}
