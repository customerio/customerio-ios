import Foundation
import SwiftUI

struct EnvironmentText: View {
var body: some View {
        VStack(spacing: 10) {
            Text("SDK: \(EnvironmentUtil.cioSdkVersion)")
            Text("app: \(EnvironmentUtil.appBuildVersion) (\(EnvironmentUtil.appBuildNumber))")
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
