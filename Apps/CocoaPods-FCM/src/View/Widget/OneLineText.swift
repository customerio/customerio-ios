import Foundation
import SwiftUI

// Text view that can only be 1 line long. Cut off the text at the end if the text cannot fit on screen.
struct OneLineText: View {
    let ellipsis: Bool
    let title: String

    init(_ title: String, ellipsis: Bool = true) {
        self.title = title
        self.ellipsis = ellipsis
    }

    var body: some View {
        if ellipsis {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(title)
                .lineLimit(1)
        }
    }
}
