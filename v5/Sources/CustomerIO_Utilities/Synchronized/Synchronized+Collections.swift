extension Synchronized where T: Collection {
    public var count: Int {
        using { value in value.count }
    }

    public var isEmpty: Bool {
        using { value in value.isEmpty }
    }
}

extension Synchronized where T: MutableCollection {
    /// Accesses the element at `position` in a thread-safe manner.
    ///
    /// - Warning: The getter and setter each acquire the lock independently.
    ///   Chained compound mutations such as `sync[i].property = value` are
    ///   **not** atomic — use `mutating { $0[i].property = value }` instead.
    public subscript(position: T.Index) -> T.Element {
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

extension Synchronized where T: RangeReplaceableCollection {
    public static func += <S>(lhs: Synchronized<T>, rhs: S)
    where S: Sequence, T.Element == S.Element {
        lhs.append(contentsOf: rhs)
    }

    public static func += (lhs: Synchronized<T>, rhs: T.Element) {
        lhs.append(rhs)
    }

    public func append(_ newElement: T.Element) {
        mutating { value in
            value.append(newElement)
        }
    }

    public func append<S>(contentsOf newElements: S) where S: Sequence, T.Element == S.Element {
        mutating { value in
            value.append(contentsOf: newElements)
        }
    }

    public func insert(_ newElement: T.Element, at i: T.Index) {
        mutating { value in
            value.insert(newElement, at: i)
        }
    }

    public func insert<S>(contentsOf newElements: S, at i: T.Index)
    where S: Collection, T.Element == S.Element {
        mutating { value in
            value.insert(contentsOf: newElements, at: i)
        }
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        mutating { value in
            value.removeAll(keepingCapacity: keepCapacity)
        }
    }

    public func removeAll(where matching: (T.Element) throws -> Bool) rethrows {
        try mutating { value in
            try value.removeAll(where: matching)
        }
    }

}
