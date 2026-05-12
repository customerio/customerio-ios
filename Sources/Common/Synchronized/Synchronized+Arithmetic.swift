public extension Synchronized where T: AdditiveArithmetic {
    static func + (lhs: Synchronized<T>, rhs: T) -> T {
        lhs.using { lhsValue in
            lhsValue + rhs
        }
    }

    static func - (lhs: Synchronized<T>, rhs: T) -> T {
        lhs.using { lhsValue in
            lhsValue - rhs
        }
    }

    static func += (lhs: Synchronized<T>, rhs: T) {
        lhs.mutating { lhsValue in
            lhsValue += rhs
        }
    }

    static func -= (lhs: Synchronized<T>, rhs: T) {
        lhs.mutating { lhsValue in
            lhsValue -= rhs
        }
    }
}
