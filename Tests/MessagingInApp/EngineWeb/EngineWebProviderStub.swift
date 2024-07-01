@testable import CioMessagingInApp
import Foundation
import UIKit

class EngineWebProviderStub: EngineWebProvider {
    func getEngineWebInstance(configuration: EngineWebConfiguration) -> EngineWebInstance {
        let newMock = EngineWebInstanceMock()

        // Set defaults on the mock to make it useable in tests.
        newMock.view = UIView() // Code expects Engine to return a View that displays in-app message. Return any View to get code under test to run.

        return newMock
    }
}
