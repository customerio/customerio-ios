@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class VersionTest: XCTestCase {
    func test_versionValidSemanticVersion() {
        // regex: https://regexr.com/662d5
        XCTAssertTrue(SdkVersion.version.matches(regex: #"(\d+)\.(\d+)\.(\d+)((-alpha|-beta)\.\d+)*"#))
    }
}
