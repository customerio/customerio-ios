extension Synchronized where T: Comparable {
    public static func < (lhs: Synchronized<T>, rhs: T) -> Bool {
        lhs.using { lhsValue in
            lhsValue < rhs
        }
    }

    public static func <= (lhs: Synchronized<T>, rhs: T) -> Bool {
        lhs.using { lhsValue in
            lhsValue <= rhs
        }
    }

    public static func > (lhs: Synchronized<T>, rhs: T) -> Bool {
        lhs.using { lhsValue in
            lhsValue > rhs
        }
    }

    public static func >= (lhs: Synchronized<T>, rhs: T) -> Bool {
        lhs.using { lhsValue in
            lhsValue >= rhs
        }
    }
}
