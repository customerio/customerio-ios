extension Synchronized: Comparable where T: Comparable {
    public static func < (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Bool {
        guard lhs !== rhs else { return false }

        return lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue < rhsValue
            }
        }
    }

    public static func <= (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Bool {
        guard lhs !== rhs else { return true }

        return lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue <= rhsValue
            }
        }
    }

    public static func > (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Bool {
        guard lhs !== rhs else { return false }

        return lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue > rhsValue
            }
        }
    }

    public static func >= (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Bool {
        guard lhs !== rhs else { return true }

        return lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue >= rhsValue
            }
        }
    }
}

// MARK: - Comparable with rhs that isn't wrapped with Synchronized

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
