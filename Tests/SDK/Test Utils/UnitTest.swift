@testable import CIO
import Foundation
import XCTest

class UnitTest: XCTestCase {
    // Prefer to use real instance of key value storage because (1) mocking it is annoying and (2) tests react closely to real app.
    var keyValueStorage: KeyValueStorage!
    private let userDefaults = DI.shared.userDefaults

    override func setUp() {
        keyValueStorage = UserDefaultsKeyValueStorage(userDefaults: userDefaults)

        deleteAll()

        super.setUp()
    }

    override func tearDown() {
        deleteAll()

        DI.shared.resetOverrides()

        super.tearDown()
    }

    func deleteAll() {
        deleteUserDefaults()
    }

    // It's important you only do this in the tests code, not the SDK code. We do *not* want to delete userdefault values for the customer's app by accident.
    private func deleteUserDefaults() {
        userDefaults.dictionaryRepresentation().keys.forEach { userDefaults.removeObject(forKey: $0) }
    }
}
