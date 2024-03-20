import MarkdownUI
import SwiftUI

enum CIOExample: String, CaseIterable {
    case initialize, identify, track, profileAttributes, deviceAttributes
    var title: String {
        switch self {
        case .initialize:
            "Initialize"
        case .identify:
            "Identify"
        case .track:
            "Event Tracking"
        case .profileAttributes:
            "Profile Attributes"
        case .deviceAttributes:
            "Device Attributes"
        }
    }
}

struct MainLayoutView<ContentView: View>: View {
    @EnvironmentObject private var viewModel: ViewModel

    @Binding var selectedExample: CIOExample

    @ViewBuilder var contentView: ContentView

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    Text("Customer.io &")
                        .font(.extraLargeTitle)
                    Image(systemName: "visionpro.fill")
                        .font(.extraLargeTitle)
                    Spacer()
                    Logo()
                }
                .frame(height: 50)
                .clipped()
                .padding(.horizontal, 24)

                HStack(alignment: .top) {
                    List(CIOExample.allCases, id: \.self) { example in
                        Text(example.title)
                            .foregroundColor(example == selectedExample ? .accentColor : .primary)
                            .onTapGesture {
                                withAnimation {
                                    selectedExample = example
                                }
                            }
                    }
                    .frame(width: 320)

                    contentView
                }

                Spacer()
            }
            .markdownTheme(.tutorial)
            .markdownCodeSyntaxHighlighter(.splash)

            .padding([.top, .trailing], 24)
            .textFieldStyle(.roundedBorder)

            VStack {
                Spacer()
                ErrorToastView(error: $viewModel.errorMessage)
                SuccessToastView(message: $viewModel.successMessage)
            }
        }
        .buttonStyle(CustomButtonStyle())
    }
}

struct CustomButtonStyle: PrimitiveButtonStyle {
    typealias Body = Button
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .background(Color(rgba: 0x333333FF))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundColor(Color.white)
    }
}

#Preview {
    MainLayoutView(selectedExample: .constant(.initialize)) {
        Text("Hello World")
        FloatingTitleTextField(title: "Field", text: .constant("value"))
        Button("Some button") {}
    }
}
