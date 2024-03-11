import MarkdownUI
import SwiftUI

struct CommonLayoutView<ContentView: View>: View {
    @EnvironmentObject private var viewModel: ViewModel

    @ViewBuilder var contentView: ContentView

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    TutorialsMenuView()

                    Markdown {
                        "## \(viewModel.titleConfig.screenTitle)"
                    }
                    if viewModel.titleConfig.showVisionProLogo {
                        Image(systemName: "visionpro.fill")
                            .font(.extraLargeTitle)
                    }
                    Spacer()

                    Logo()
                }
                .frame(height: 50)
                .clipped()
                contentView
                Spacer()
            }
            .markdownTheme(.tutorial)
            .markdownCodeSyntaxHighlighter(.splash)

            .padding([.top, .horizontal], 32)
            .padding(.bottom, 16)
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
    CommonLayoutView {
        Text("Hello World")
        FloatingTitleTextField(title: "Field", text: .constant("value"))
        Button("Some button") {}
    }
}
