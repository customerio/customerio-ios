public extension Synchronized where T: Comparable {
    static func < (lhs: Synchronized<T>, rhs: T) -> Bool {
        lhs.using { lhsValue in
            lhsValue < rhs
        }
    }

    static func <= (lhs: Synchronized<T>, rhs: T) -> Bool {
        lhs.using { lhsValue in
            lhsValue <= rhs
        }
    }

    static func > (lhs: Synchronized<T>, rhs: T) -> Bool {
        lhs.using { lhsValue in
            lhsValue > rhs
        }
    }

    static func >= (lhs: Synchronized<T>, rhs: T) -> Bool {
        lhs.using { lhsValue in
            lhsValue >= rhs
        }
    }
}
