import MarkdownUI
import SwiftUI

struct PropertiesInputView: View {
    @EnvironmentObject var viewModel: ViewModel
    @Binding var properties: [Property]
    let addPropertiesLabel: String
    
    var enableRemovingProperties = true

    @State private var additionalPropertyName: String = ""
    @State private var additionalPropertyValue: String = ""

    func onAddProperty() {
        let name = additionalPropertyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = additionalPropertyValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !name.isEmpty, !value.isEmpty {
            guard properties.firstIndex(where: { p in
                p.name == name
            }) == nil else {
                viewModel.errorMessage = "Property with the same name already exists"
                return
            }
            
            let addedProperty = Property(
                name: name,
                value: value
            )
            additionalPropertyName = ""
            additionalPropertyValue = ""
            properties.append(addedProperty)
        } else {
            viewModel.errorMessage = "Please enter both property name and value"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach($properties) { p in
                HStack(alignment: .bottom) {
                    FloatingTitleTextField(title: "Property name", text: p.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    FloatingTitleTextField(title: "Property Value", text: p.value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    if enableRemovingProperties {
                        Button {
                            if let pIndex = properties.firstIndex(of: p.wrappedValue) {
                                properties.remove(at: pIndex)
                            }
                            
                            
                        } label: {
                            Image(systemName: "minus")
                                .font(.largeTitle)
                        }
                    }
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
    PropertiesInputView(properties: .constant([
    Property(name: "name", value: ""),
    Property(name: "email", value: "")
    ]), addPropertiesLabel: "Add more properties?")
}
