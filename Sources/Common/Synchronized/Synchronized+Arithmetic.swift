extension Synchronized where T: AdditiveArithmetic {
    public static func + (lhs: Synchronized<T>, rhs: T) -> T {
        lhs.using { lhsValue in
            lhsValue + rhs
        }
    }

    public static func - (lhs: Synchronized<T>, rhs: T) -> T {
        lhs.using { lhsValue in
            lhsValue - rhs
        }
    }

    public static func += (lhs: Synchronized<T>, rhs: T) {
        lhs.mutating { lhsValue in
            lhsValue += rhs
        }
    }

    public static func -= (lhs: Synchronized<T>, rhs: T) {
        lhs.mutating { lhsValue in
            lhsValue -= rhs
        }
    }
}
