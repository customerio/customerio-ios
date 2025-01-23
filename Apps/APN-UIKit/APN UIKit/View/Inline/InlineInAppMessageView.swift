import CioMessagingInApp
import SwiftUI

struct InlineInAppMessageView: View {
    var body: some View {
        VStack {
            InlineMessage(elementId: "sticky-header")
                .frame(maxWidth: .infinity)

            ScrollView {
                CardView()
                    .frame(maxWidth: .infinity)

                RectangleView()

                SquaresView()
                    .frame(height: 160)

                InlineMessage(elementId: "inline")
                    .frame(maxWidth: .infinity)

                CardView()
                    .frame(maxWidth: .infinity)

                RectangleView()

                CardView()
                    .frame(maxWidth: .infinity)

                RectangleView()

                InlineMessage(elementId: "below-fold")
                    .frame(maxWidth: .infinity)

            }.padding(.horizontal, 10)
        }
    }
}

struct RectangleView: View {
    var body: some View {
        Rectangle()
            .fill(Color.lightBlue)
            .frame(height: 160)
            .frame(maxWidth: .infinity)
    }
}

struct CardView: View {
    var body: some View {
        HStack(spacing: 20) {
            Color.lightBlue
                .frame(width: 150, height: 120)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 5) {
                Color.lightBlue
                    .frame(width: 120, height: 15)
                    .cornerRadius(4)

                Color.lightBlue
                    .frame(width: 100, height: 15)
                    .cornerRadius(4)

                Spacer()
                    .frame(height: 15)

                Color.lightBlue
                    .frame(width: 80, height: 30)
                    .cornerRadius(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 120)
        }
    }
}

struct SquaresView: View {
    var body: some View {
        HStack {
            Color.lightBlue
                .frame(minWidth: 0, maxWidth: .infinity)

            Color.lightBlue
                .frame(minWidth: 0, maxWidth: .infinity)

            Color.lightBlue
                .frame(minWidth: 0, maxWidth: .infinity)
        }
    }
}

#Preview {
    InlineInAppMessageView()
}
