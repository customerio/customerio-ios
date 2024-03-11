import SwiftUI

struct HLineView: View {
    var body: some View {
        Rectangle()
            .background(.placeholder.opacity(0.5))
            .frame(height: 0.5)
    }
}

struct VLineView: View {
    var body: some View {
        Rectangle()
            .background(.placeholder.opacity(0.5))
            .frame(width: 0.5)
    }
}

#Preview {
    ZStack {
        HLineView()
        VLineView()
    }
}
