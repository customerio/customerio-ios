import Foundation
import Testing

@testable
import CioInternalCommon


struct AtomicTest {
    
    class TestObject {
        @Atomic
        var text: String
        init(text: String = "") {
            self.text = text
        }
    }

    @Test
    func test_givenCallSetWithNewValue_expectGetCallReceivesNewValue() throws {
        let expect = "new value"

        let testObject = TestObject()
        testObject.text = expect
        
        let actual = testObject.text

        #expect(expect == actual)
    }

    @Test
    func test_givenSetAndGetDifferentThreads_expectGetNewlySetValue() throws {
        let expect = "new value"

        let testObject = TestObject()

        DispatchQueue.global(qos: .background).sync {
            testObject.text = expect
        }

        let actual = testObject.text

        #expect(expect == actual)
    }
}
