import Foundation
import SwiftUI

extension Color {
    static var random: Color {
        let colors: [Color] = [
            .purple,
            .blue,
            .red,
            .green,
            .orange,
            .pink,
            .yellow
        ]

        return colors.randomElement()!
    }
}
