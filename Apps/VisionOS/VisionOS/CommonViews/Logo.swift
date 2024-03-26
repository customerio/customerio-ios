import SwiftUI

struct Logo: View {
    var body: some View {
        Image("logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 50)
    }
}

#Preview {
    Logo()
}
