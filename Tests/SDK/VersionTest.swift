@testable import CIO
import Foundation
import XCTest

class VersionTest: XCTestCase {
    func test_versionValidSemanticVersion() {
        // regex: https://regexr.com/63gj6
        XCTAssertTrue(SdkVersion.version.matches(regex: #"(\d+)\.(\d+)\.(\d+)(-alpha|-beta)*"#))
    }
}
