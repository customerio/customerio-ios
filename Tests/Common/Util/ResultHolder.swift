import Foundation

actor ResultHolder {
    var results: [Bool]

    init(count: Int) {
        self.results = [Bool](repeating: false, count: count)
    }

    func updateResult(at index: Int, with value: Bool) {
        results[index] = value
    }
}
