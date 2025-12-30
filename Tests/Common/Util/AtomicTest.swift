@testable import CioInternalCommon

import Dispatch
import Foundation
import Testing

struct AtomicTest {
    struct AtomicTestStruct {
        @Atomic var value: String?
        init() {}
    }

    class AtomicTestObject {
        @Atomic var value: String?
        init() {}
    }

    @Test
    func testSetValueIsAlsoFetchedOnStruct() {
        var atomic = AtomicTestStruct()

        let initial = "new value"
        atomic.value = initial
        let fetched = atomic.value

        #expect(initial == fetched)
    }

    @Test
    func testSetValueIsAlsoFetchedOnObject() {
        let atomic = AtomicTestObject()

        let initial = "new value"
        atomic.value = initial
        let fetched = atomic.value

        #expect(initial == fetched)
    }

    @Test
    func testSetValueFromBackgroundOnStruct() {
        var atomic = AtomicTestStruct()

        let initial = "new value"

        DispatchQueue.global(qos: .background).sync {
            atomic.value = initial
        }

        let fetched = atomic.value

        #expect(initial == fetched)
    }

    @Test
    func testSetValueFromBackgroundOnObject() {
        let atomic = AtomicTestObject()

        let initial = "new value"

        DispatchQueue.global(qos: .background).sync {
            atomic.value = initial
        }

        let fetched = atomic.value

        #expect(initial == fetched)
    }
}
