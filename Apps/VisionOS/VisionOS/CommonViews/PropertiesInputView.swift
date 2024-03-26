import MarkdownUI
import SwiftUI

enum PropertiesTerminology: String {
    case properties, traits, attributes

    var capitalize: String {
        "\(self)".capitalized
    }
}

struct PropertiesInputView: View {
    @EnvironmentObject private var viewModel: ViewModel

    let terminology: PropertiesTerminology
    var showCodableHint: Bool = false

    @Binding var properties: [Property]

    @State private var additionalPropertyName: String = ""
    @State private var additionalPropertyValue: String = ""

    func onAddProperty() {
        let name = additionalPropertyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = additionalPropertyValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if !name.isEmpty, !value.isEmpty {
            guard properties.firstIndex(where: { p in
                p.key == name
            }) == nil else {
                viewModel.errorMessage = "An entry with the same key already exists"
                return
            }

            let addedProperty = Property(
                key: name,
                value: value
            )
            additionalPropertyName = ""
            additionalPropertyValue = ""
            properties.append(addedProperty)
        } else {
            viewModel.errorMessage = "Please enter a key and its value"
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(terminology.capitalize)
                .font(.title)

            if showCodableHint {
                Text("\(terminology.capitalize)' values can be any type that conforms to the Codable protocol. For simplicity we are using string values in this example.")
                    .font(.callout)
                    .italic()
            }

            ForEach($properties) { p in
                HStack(alignment: .bottom) {
                    FloatingTitleTextField(title: "Key", text: p.key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    FloatingTitleTextField(title: "Value", text: p.value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

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

            HStack(alignment: .bottom) {
                FloatingTitleTextField(
                    title: "Key",
                    text: $additionalPropertyName
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    onAddProperty()
                }

                FloatingTitleTextField(
                    title: "Value",
                    text: $additionalPropertyValue
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(onAddProperty)

                Button(action: onAddProperty) {
                    Image(systemName: "plus")
                        .font(.largeTitle)
                }
            }
        }
    }
}

#Preview {
    PropertiesInputView(
        terminology: .properties,
        properties: .constant([
            Property(key: "name", value: ""),
            Property(key: "email", value: "")
        ])
    )
}
