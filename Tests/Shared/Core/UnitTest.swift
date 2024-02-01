@testable import CioInternalCommon
import Foundation
import XCTest

/**
 Handy base class for tests in this test suite. Extend this class to have access to some handy properties and functions you
 may want to use in your tests.

 We use a base class instead of simply a utility class because we can't access `setup` and `teardown` functions with a util class.
 */

///
open class UnitTest: UnitTestBase<CustomerIO> {}
