import MarkdownUI
import SwiftUI

private extension Color {
    static let codeBackground = Color(rgba: 0x333336FF)
    static let blockquoteIcon = Color(rgba: 0xFECD00FF)
    static let blockquoteBackground = Color(rgba: 0xAF65FFFF)
    static let linkColor = Color(rgba: 0x04ECBBFF)
}

extension Theme {
    static let tutorial = Theme.docC
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(16)
            FontStyle(.italic)
            FontWeight(.bold)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.333335))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(22)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
            }
            .background(Color.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
        }
        .text {
            FontSize(22)
        }
        .link {
            ForegroundColor(Color.linkColor)
            FontWeight(.semibold)
            UnderlineStyle(.single)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                Image(systemName: "exclamationmark.warninglight.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60)
                    .rotationEffect(.degrees(180))
                    .foregroundColor(Color.blockquoteIcon)
                    .padding(.horizontal)
                configuration.label
                    .relativePadding(.vertical, length: .em(0.3))
                    .relativePadding(.trailing, length: .em(1))
            }
            .background(Color.blockquoteBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .fixedSize(horizontal: false, vertical: true)
        }
}
