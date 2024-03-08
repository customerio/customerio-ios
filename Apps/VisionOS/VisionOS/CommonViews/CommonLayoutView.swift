import MarkdownUI
import SwiftUI

struct CommonLayoutView<ContentView: View>: View {
    @ObservedObject var state = AppState.shared

    @ViewBuilder var contentView: ContentView

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    TutorialsMenuView()

                    Markdown {
                        "## \(state.titleConfig.screenTitle)"
                    }
                    if state.titleConfig.showVisionProLogo {
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
                ErrorToastView(error: $state.errorMessage)
                SuccessToastView(message: $state.successMessage)
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
