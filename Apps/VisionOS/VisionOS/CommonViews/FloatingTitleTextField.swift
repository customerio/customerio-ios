import SwiftUI

struct FloatingTitleTextField: View {
    let title: String
    let text: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundColor(
                text.wrappedValue.isEmpty ? Color(.placeholderText) : .white)
                .opacity(text.wrappedValue.isEmpty ? 0 : 1)
                .offset(y: text.wrappedValue.isEmpty ? 20 : 0)

            TextField(title, text: text)
        }
        .animation(.easeInOut, value: text.wrappedValue)
    }
}

#Preview {
    MainLayoutView(selectedExample: .constant(.initialize)) {
        FloatingTitleTextField(title: "Email", text: .constant("email@example.com"))
        FloatingTitleTextField(title: "Empty text", text: .constant(""))
    }
}
