import MarkdownUI
import SwiftUI

struct PropertiesInputView: View {
    @ObservedObject var state = AppState.shared
    @Binding var properties: [Property]
    let addPropertiesLabel: String

    @State private var additionalPropertyName: String = ""
    @State private var additionalPropertyValue: String = ""

    func onAddProperty() {
        
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach($properties) { p in
                HStack(alignment: .top) {
                    FloatingTitleTextField(title: "Property name", text: p.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    FloatingTitleTextField(title: "Property Value", text: p.value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            HLineView()
            HStack(alignment: .bottom) {
                FloatingTitleTextField(
                    title: "Property name",
                    text: $additionalPropertyName
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    onAddProperty()
                }

                FloatingTitleTextField(
                    title: "Property Value",
                    text: $additionalPropertyValue
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    onAddProperty()
                }

                Button(action: onAddProperty) {
                    Image(systemName: "plus")
                        .font(.largeTitle)
                }
            }
            Markdown {
                addPropertiesLabel
            }
        }
        
    }
}

#Preview {
    PropertiesInputView(properties: .constant([]), addPropertiesLabel: "Add more properties?")
}
