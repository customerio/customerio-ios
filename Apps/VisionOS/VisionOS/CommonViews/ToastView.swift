import SwiftUI

struct ErrorToastView: View {
    @Binding var error: String
    var body: some View {
        ToastView(message: $error, icon: Image(systemName: "xmark.circle.fill"), backgroundColor: .red)
    }
}

struct SuccessToastView: View {
    @Binding var message: String
    var body: some View {
        ToastView(message: $message, icon: Image(systemName: "checkmark.rectangle.portrait.fill"), backgroundColor: .green)
    }
}

struct ToastView: View {
    @Binding var message: String
    let icon: Image
    let backgroundColor: Color

    var body: some View {
        Label(
            title: { Text(message) },
            icon: { icon }
        )
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .font(.system(size: 24))
        .fontDesign(.rounded)
        .background(backgroundColor)
        .opacity(message.isEmpty ? 0 : 1)
        .onChange(of: message) {
            if message.isEmpty {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if !message.isEmpty {
                    withAnimation {
                        message = ""
                    }
                }
            }
        }
    }
}

#Preview {
    TabView {
        VStack {
            Spacer()
            ErrorToastView(error: .constant(""))
            ErrorToastView(error: .constant("Something went wrong"))
        }.frame(width: .infinity)

        VStack {
            Spacer()
            SuccessToastView(message: .constant(""))
            SuccessToastView(message: .constant("Success"))
        }.frame(width: .infinity)
    }.tabViewStyle(.page)
}
