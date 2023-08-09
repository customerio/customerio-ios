import Foundation
import SwiftUI

struct EnvironmentText: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Customer.io iOS SDK \(EnvironmentUtil.cioSdkVersion)")
            Text("\(EnvironmentUtil.appName) \(EnvironmentUtil.appBuildVersion) (\(EnvironmentUtil.appBuildNumber))")
        }
        .multilineTextAlignment(.center)
        .foregroundColor(.gray)
        .padding(10)
    }
}

struct EnvironmentText_Previews: PreviewProvider {
    static var previews: some View {
        EnvironmentText()
    }
}
