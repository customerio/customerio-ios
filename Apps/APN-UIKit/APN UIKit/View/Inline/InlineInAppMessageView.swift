import SwiftUI

struct InlineInAppMessageView: View {
    var body: some View {
        VStack(spacing: 10) {
            // To be replaced with inline view
            HeaderView()
                .frame(height: 80)
                .frame(maxWidth: .infinity)
                .background(Color.red)

            ScrollView {
                CardView()
                    .frame(maxWidth: .infinity)

                RectangleView()

                SquaresView()
                    .frame(height: 160)

                // To be replaced with inline view
                Text("#inline")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
                    .background(Color.red)

                CardView()
                    .frame(maxWidth: .infinity)

                RectangleView()

                CardView()
                    .frame(maxWidth: .infinity)

                RectangleView()

                // To be replaced with inline view
                Text("#below-fold")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
                    .background(Color.red)

            }.padding()
        }
    }
}

struct HeaderView: View {
    var body: some View {
        Text("#sticky-header")
            .font(.subheadline)
            .foregroundColor(.white)
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
