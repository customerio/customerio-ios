@testable import CioMessagingInApp
import Foundation
import UIKit

class EngineWebProviderStub: EngineWebProvider {
    let engineWebMock: EngineWebInstance

    init(engineWebMock: EngineWebInstance) {
        self.engineWebMock = engineWebMock
    }

    func getEngineWebInstance(configuration: EngineWebConfiguration) -> EngineWebInstance {
        engineWebMock
    }
}

// In order to test multiple instances of inline Views, you need to create multiple separate EngineWebInstance instances for each View instance.
// This is a new stub that allows this.
// A follow-up refactor that makes this stub the default would be a good chance to the test suite.
class EngineWebProviderStub2: EngineWebProvider {
    func getEngineWebInstance(configuration: EngineWebConfiguration) -> EngineWebInstance {
        let newMock = EngineWebInstanceMock()

        // Set defaults on the mock to make it useable in tests.
        newMock.view = UIView() // Code expects Engine to return a View that displays in-app message. Return any View to get code under test to run.

        return newMock
    }
}
