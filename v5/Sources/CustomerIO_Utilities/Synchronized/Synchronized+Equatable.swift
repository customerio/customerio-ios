extension Synchronized: Equatable where T: Equatable {
    public static func == (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Bool {
        guard lhs !== rhs else { return true }

        return lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue == rhsValue
            }
        }
    }

    // Although not strictly necessary, we provide this operator to ensure threading is done correctly
    public static func != (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Bool {
        guard lhs !== rhs else { return false }

        return lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue != rhsValue
            }
        }
    }

    public static func == (lhs: Synchronized<T>, rhs: T) -> Bool {
        lhs.using { lhsValue in
            lhsValue == rhs
        }
    }

    // Although not strictly necessary, we provide this operator to ensure threading is done correctly
    public static func != (lhs: Synchronized<T>, rhs: T) -> Bool {
        lhs.using { lhsValue in
            lhsValue != rhs
        }
    }
}
