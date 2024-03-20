import Foundation

class ViewModel: ObservableObject {
    @Published var errorMessage: String = ""
    @Published var successMessage: String = ""
}
