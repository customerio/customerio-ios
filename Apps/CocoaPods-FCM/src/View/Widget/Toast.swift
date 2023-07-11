import Foundation
import SwiftUI

struct ToastView: View {
    @Binding var message: String?
    let duration: TimeInterval
    private let timer = SwiftUITimer()

    var body: some View {
        ZStack(alignment: .top) {
            if let message = message, !message.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(message)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black)
                            .cornerRadius(10)
                        Spacer()
                    }
                }
            }
        }
        .onChange(of: message) { message in
            if let message = message, !message.isEmpty {
                timer.start(interval: duration) {
                    self.message = nil
                }
            }
        }
    }
}
