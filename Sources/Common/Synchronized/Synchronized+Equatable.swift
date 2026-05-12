extension Synchronized: Equatable where T: Equatable {
    // Locks are always acquired in ObjectIdentifier order so that concurrent calls to
    // `a == b` and `b == a` on different threads cannot produce an ABBA deadlock.
    public static func == (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Bool {
        guard lhs !== rhs else { return true }

        if ObjectIdentifier(lhs) < ObjectIdentifier(rhs) {
            return lhs.using { lhsValue in rhs.using { lhsValue == $0 } }
        } else {
            return rhs.using { rhsValue in lhs.using { $0 == rhsValue } }
        }
    }

    public static func == (lhs: Synchronized<T>, rhs: T) -> Bool {
        lhs.using { lhsValue in
            lhsValue == rhs
        }
    }

    public static func != (lhs: Synchronized<T>, rhs: T) -> Bool {
        lhs.using { lhsValue in
            lhsValue != rhs
        }
    }
}
