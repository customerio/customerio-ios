extension Synchronized where T: AdditiveArithmetic {
    public static func + (lhs: Synchronized<T>, rhs: Synchronized<T>) -> T {
        guard lhs !== rhs else {
            return lhs.using { value in
                value + value
            }
        }

        return lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue + rhsValue
            }
        }
    }

    public static func + (lhs: Synchronized<T>, rhs: T) -> T {
        lhs.using { lhsValue in
            lhsValue + rhs
        }
    }

    public static func - (lhs: Synchronized<T>, rhs: Synchronized<T>) -> T {
        guard lhs !== rhs else { return .zero }

        return lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue - rhsValue
            }
        }
    }

    public static func - (lhs: Synchronized<T>, rhs: T) -> T {
        lhs.using { lhsValue in
            lhsValue - rhs
        }
    }

    public static func += (lhs: Synchronized<T>, rhs: Synchronized<T>) {
        guard lhs !== rhs else {
            lhs.mutating { value in
                value += value
            }
            return
        }
        lhs.mutating { lhsValue in
            rhs.using { rhsValue in
                lhsValue += rhsValue
            }
        }
    }

    public static func += (lhs: Synchronized<T>, rhs: T) {
        lhs.mutating { lhsValue in
            lhsValue += rhs
        }
    }

    public static func -= (lhs: Synchronized<T>, rhs: Synchronized<T>) {
        guard lhs !== rhs else {
            lhs.wrappedValue = .zero
            return
        }

        lhs.mutating { lhsValue in
            rhs.using { rhsValue in
                lhsValue -= rhsValue
            }
        }
    }

    public static func -= (lhs: Synchronized<T>, rhs: T) {
        lhs.mutating { lhsValue in
            lhsValue -= rhs
        }
    }
}
