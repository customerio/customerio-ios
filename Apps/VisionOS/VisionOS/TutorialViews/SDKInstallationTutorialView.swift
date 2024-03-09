import MarkdownUI
import SwiftUI

struct SDKInstallationTutorialView: View {
    static let title = ScreenTitleConfig("SDK Installation")
    @ObservedObject var state = AppState.shared
    @EnvironmentObject private var viewModel: ViewModel
    var body: some View {
        Markdown {
"""
You can install CustomerIO Swift SDKs
using either Swift Package Manager (SPM) or Cocoapods.

There are few packages for Swift, but for now you only need the `Tracking` package.
We will get to the other packages later.

**SPM:**
Add the dependencies from the repo:
`https://github.com/customerio/customerio-ios.git` and add only the tracking
package

**Cocoapods:** Add the following pod to your Podfile

```bash
CustomerIO/Tracking
```

Once done, make sure your app builds and runs as expected.
[Let's setup the sdk](\(InlineNavigationLink.setup))
"""
        }
        .onAppear {
            viewModel.titleConfig = Self.title
        }
    }
}

#Preview {
    CommonLayoutView {
        SDKInstallationTutorialView()
    }
}
