import SwiftUI
import CioMessagingInApp
import CioDataPipelines

struct InlineInAppView: View {
    
    @Binding var navPath: [NavScreen]
    
    var body: some View {
        VStack {
            InlineMessageView(elementId: "ios-landing") { actionName in
                if actionName == "banner" {
                    navPath.append(.bannerDemo)
                } else {
                    navPath.append(.contentDemo)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    InlineInAppView(navPath: .constant([]))
}
