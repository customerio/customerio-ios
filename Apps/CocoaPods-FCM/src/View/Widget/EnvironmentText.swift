import Foundation
import SwiftUI

struct EnvironmentText: View {
    var body: some View {
        Text("SDK: \(EnvironmentUtil.cioSdkVersion) \n app: \(EnvironmentUtil.appBuildVersion) (\(EnvironmentUtil.appBuildNumber))")
            .multilineTextAlignment(.center)
            .foregroundColor(.gray)
    }
}

struct EnvironmentText_Previews: PreviewProvider {
    static var previews: some View {
        EnvironmentText()
    }
}
