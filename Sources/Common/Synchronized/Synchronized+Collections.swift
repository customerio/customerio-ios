public extension Synchronized where T: Collection {
    var count: Int {
        using { value in value.count }
    }

    var isEmpty: Bool {
        using { value in value.isEmpty }
    }
}

public extension Synchronized where T: MutableCollection {
    /// Accesses the element at `position` in a thread-safe manner.
    ///
    /// - Warning: The getter and setter each acquire the lock independently.
    ///   Chained compound mutations such as `sync[i].property = value` are
    ///   **not** atomic — use `mutating { $0[i].property = value }` instead.
    subscript(position: T.Index) -> T.Element {
        get {
            using { value in
                value[position]
            }
        }
        set {
            mutating { value in
                value[position] = newValue
            }
        }
    }
}

public extension Synchronized where T: RangeReplaceableCollection {
    static func += <S>(lhs: Synchronized<T>, rhs: S)
        where S: Sequence, T.Element == S.Element {
        lhs.append(contentsOf: rhs)
    }

    static func += (lhs: Synchronized<T>, rhs: T.Element) {
        lhs.append(rhs)
    }

    func append(_ newElement: T.Element) {
        mutating { value in
            value.append(newElement)
        }
    }

    func append<S>(contentsOf newElements: S) where S: Sequence, T.Element == S.Element {
        mutating { value in
            value.append(contentsOf: newElements)
        }
    }

    func insert(_ newElement: T.Element, at i: T.Index) {
        mutating { value in
            value.insert(newElement, at: i)
        }
    }

    func insert<S>(contentsOf newElements: S, at i: T.Index)
        where S: Collection, T.Element == S.Element {
        mutating { value in
            value.insert(contentsOf: newElements, at: i)
        }
    }

    func removeAll(keepingCapacity keepCapacity: Bool = false) {
        mutating { value in
            value.removeAll(keepingCapacity: keepCapacity)
        }
    }

    func removeAll(where matching: (T.Element) throws -> Bool) rethrows {
        try mutating { value in
            try value.removeAll(where: matching)
        }
    }
}
