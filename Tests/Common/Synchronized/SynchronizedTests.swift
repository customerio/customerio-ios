import Dispatch
import Testing

@testable import CioInternalCommon

// MARK: - Core read/write

@Suite struct SynchronizedCoreTests {

    @Test func wrappedValueGetSet() {
        let box = Synchronized(42)
        #expect(box.wrappedValue == 42)
        box.wrappedValue = 99
        #expect(box.wrappedValue == 99)
    }

    @Test func mutatingReturnsResult() {
        let box = Synchronized("hello")
        let old = box.mutating { value -> String in
            let previous = value
            value = "world"
            return previous
        }
        #expect(old == "hello")
        #expect(box.wrappedValue == "world")
    }

    @Test func mutatingThrows() {
        struct TestError: Error {}
        let box = Synchronized(0)
        #expect(throws: TestError.self) {
            try box.mutating { _ in throw TestError() }
        }
    }

    @Test func usingDoesNotMutate() {
        let box = Synchronized([1, 2, 3])
        let sum = box.using { $0.reduce(0, +) }
        #expect(sum == 6)
        #expect(box.wrappedValue == [1, 2, 3])
    }

    @Test func usingThrows() {
        struct TestError: Error {}
        let box = Synchronized(0)
        #expect(throws: TestError.self) {
            try box.using { _ in throw TestError() }
        }
    }

    @Test func atomicSetAndFetch() {
        let box = Synchronized(10)
        let old = box.atomicSetAndFetch(20)
        #expect(old == 10)
        #expect(box.wrappedValue == 20)
    }

    @Test func concurrentWritesSafelyAccumulate() async {
        let box = Synchronized(0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    box.mutating { $0 += 1 }
                }
            }
        }
        #expect(box.wrappedValue == 100)
    }
}

// MARK: - Arithmetic

@Suite struct SynchronizedArithmeticTests {

    @Test func addRawValue() {
        let a = Synchronized(10)
        #expect(a + 5 == 15)
    }

    @Test func subtractRawValue() {
        let a = Synchronized(10)
        #expect(a - 4 == 6)
    }

    @Test func addAssignRawValue() {
        let a = Synchronized(5)
        a += 3
        #expect(a.wrappedValue == 8)
    }

    @Test func subtractAssignRawValue() {
        let a = Synchronized(10)
        a -= 4
        #expect(a.wrappedValue == 6)
    }
}

// MARK: - Bool

@Suite struct SynchronizedBoolTests {

    @Test func toggle() {
        let flag = Synchronized(false)
        flag.toggle()
        #expect(flag.wrappedValue == true)
        flag.toggle()
        #expect(flag.wrappedValue == false)
    }
}

// MARK: - Collections

@Suite struct SynchronizedCollectionTests {

    @Test func countAndIsEmpty() {
        let list: Synchronized<[Int]> = Synchronized([])
        #expect(list.isEmpty)
        #expect(list.count == 0)
        list.append(1)
        #expect(!list.isEmpty)
        #expect(list.count == 1)
    }

    @Test func subscriptGetSet() {
        let list = Synchronized([10, 20, 30])
        #expect(list[1] == 20)
        list[1] = 99
        #expect(list[1] == 99)
    }

    @Test func append() {
        let list: Synchronized<[String]> = Synchronized([])
        list.append("a")
        list.append("b")
        #expect(list.wrappedValue == ["a", "b"])
    }

    @Test func appendContentsOf() {
        let list: Synchronized<[Int]> = Synchronized([1, 2])
        list.append(contentsOf: [3, 4])
        #expect(list.wrappedValue == [1, 2, 3, 4])
    }

    @Test func insertAt() {
        let list: Synchronized<[Int]> = Synchronized([1, 3])
        list.insert(2, at: 1)
        #expect(list.wrappedValue == [1, 2, 3])
    }

    @Test func insertContentsOf() {
        let list: Synchronized<[Int]> = Synchronized([1, 4])
        list.insert(contentsOf: [2, 3], at: 1)
        #expect(list.wrappedValue == [1, 2, 3, 4])
    }

    @Test func removeAll() {
        let list = Synchronized([1, 2, 3])
        list.removeAll()
        #expect(list.isEmpty)
    }

    @Test func removeAllKeepingCapacity() {
        var list = Synchronized([1, 2, 3])
        let capacityBefore = list.using { $0.capacity }
        list.removeAll(keepingCapacity: true)
        #expect(list.isEmpty)
        #expect(list.using { $0.capacity } >= capacityBefore)
    }

    @Test func removeAllWhere() {
        let list = Synchronized([1, 2, 3, 4, 5])
        list.removeAll(where: { $0 % 2 == 0 })
        #expect(list.wrappedValue == [1, 3, 5])
    }

    @Test func plusEqualsElement() {
        let list: Synchronized<[Int]> = Synchronized([1])
        list += 2
        #expect(list.wrappedValue == [1, 2])
    }

    @Test func plusEqualsSequence() {
        let list: Synchronized<[Int]> = Synchronized([1])
        list += [2, 3]
        #expect(list.wrappedValue == [1, 2, 3])
    }
}

// MARK: - Comparable

@Suite struct SynchronizedComparableTests {

    @Test func lessThanRaw() {
        let a = Synchronized(1)
        #expect(a < 5)
        #expect(!(a < 1))
    }

    @Test func lessThanOrEqualRaw() {
        let a = Synchronized(1)
        #expect(a <= 1)
        #expect(!(a <= 0))
    }

    @Test func greaterThanRaw() {
        let a = Synchronized(5)
        #expect(a > 1)
        #expect(!(a > 5))
    }

    @Test func greaterThanOrEqualRaw() {
        let a = Synchronized(5)
        #expect(a >= 5)
        #expect(!(a >= 6))
    }
}

// MARK: - Equatable

@Suite struct SynchronizedEquatableTests {

    @Test func equalBoxes() {
        let a = Synchronized("foo")
        let b = Synchronized("foo")
        #expect(a == b)
    }

    @Test func notEqualBoxes() {
        let a = Synchronized("foo")
        let b = Synchronized("bar")
        #expect(a != b)
    }

    @Test func equalRaw() {
        let a = Synchronized(42)
        #expect(a == 42)
        #expect(a != 99)
    }

    @Test func sameInstanceEqual() {
        let a = Synchronized(7)
        #expect(a == a)
        #expect(!(a != a))
    }

    // Calls a == b and b == a concurrently. Without the ObjectIdentifier lock-ordering in ==,
    // this reliably deadlocks. The 30s timeout converts a hang into a test failure.
    @Test func equalsConcurrentlyDoesNotDeadlock() {
        let a = Synchronized(1)
        let b = Synchronized(1)
        let group = DispatchGroup()

        for _ in 0..<1_000 {
            group.enter()
            DispatchQueue.global().async { _ = a == b; group.leave() }
            group.enter()
            DispatchQueue.global().async { _ = b == a; group.leave() }
        }

        #expect(group.wait(timeout: .now() + 30) == .success)
    }
}

// MARK: - Hashable

@Suite struct SynchronizedHashableTests {

    @Test func usableInSet() {
        let a = Synchronized(1)
        let b = Synchronized(2)
        let set: Set = [a, b]
        #expect(set.count == 2)
    }

    @Test func usableAsDictionaryKey() {
        let key = Synchronized("k")
        var dict: [Synchronized<String>: Int] = [:]
        dict[key] = 99
        #expect(dict[key] == 99)
    }

    @Test func hashMatchesWrappedValue() {
        let a = Synchronized(123)
        let b = Synchronized(123)
        var ha = Hasher()
        var hb = Hasher()
        a.hash(into: &ha)
        b.hash(into: &hb)
        #expect(ha.finalize() == hb.finalize())
    }
}

// MARK: - Dictionaries

@Suite struct SynchronizedDictionaryTests {

    @Test func subscriptGetSet() {
        let dict: Synchronized<[String: Int]> = Synchronized([:])
        dict["a"] = 1
        #expect(dict["a"] == 1)
        dict["a"] = nil
        #expect(dict["a"] == nil)
    }

    @Test func removeValue() {
        let dict: Synchronized<[String: Int]> = Synchronized(["x": 10])
        let removed = dict.removeValue(forKey: "x")
        #expect(removed == 10)
        #expect(dict["x"] == nil)
    }

    @Test func removeValueMissingKey() {
        let dict: Synchronized<[String: Int]> = Synchronized([:])
        let removed = dict.removeValue(forKey: "missing")
        #expect(removed == nil)
    }
}
