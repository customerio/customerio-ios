import MarkdownUI
import SwiftUI

enum CIOExample: String, CaseIterable {
    case initialize, identify, track, profileAttributes
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
        }
    }

    var enabled: Bool {
        switch self {
        case .initialize:
            return true
        case .identify, .track, .profileAttributes:
            return AppState.shared.workspaceSettings.isSet()
        }
    }
}

private func menuForegroundColor(for example: CIOExample, selected: Bool) -> Color {
    if selected {
        return .accent
    }
    return example.enabled ? .primary : .secondary
}

struct MainLayoutView<ContentView: View>: View {
    @EnvironmentObject private var viewModel: ViewModel

    @Binding var selectedExample: CIOExample

    @ViewBuilder var contentView: ContentView

    @ObservedObject private var state = AppState.shared

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    Logo()
                    Text("&")
                        .font(.extraLargeTitle)
                    Image(systemName: "visionpro.fill")
                        .font(.extraLargeTitle)
                        .foregroundColor(.accentColor)
                    Spacer()
                }
                .frame(height: 50)
                .clipped()
                .padding(.horizontal, 24)

                HStack(alignment: .top) {
                    List(CIOExample.allCases, id: \.self) { example in
                        Text(example.title)
                            .foregroundColor(menuForegroundColor(for: example, selected: selectedExample == example))
                            .onTapGesture {
                                withAnimation {
                                    if example.enabled {
                                        selectedExample = example
                                    } else {
                                        if example == .identify {
                                            viewModel.errorMessage = "You must initialize the SDK first"
                                        } else {
                                            viewModel.errorMessage = "The SDK must be initialized and user is identified before you can use \(example.title)"
                                        }
                                    }
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
