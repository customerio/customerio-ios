extension Synchronized where T == Bool {
    public func toggle() {
        mutating { value in
            value.toggle()
        }
    }
}
