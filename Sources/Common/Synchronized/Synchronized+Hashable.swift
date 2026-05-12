extension Synchronized: Hashable where T: Hashable {
    public func hash(into hasher: inout Hasher) {
        using { value in
            value.hash(into: &hasher)
        }
    }
}
