public extension Synchronized where T == Bool {
    func toggle() {
        mutating { value in
            value.toggle()
        }
    }
}
