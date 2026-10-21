@testable import CioFirebaseWrapper
import XCTest

private final class SignatureFixture: NSObject {
    @objc func returnsNothing() {}
    @objc func returnsObject() -> NSObject? {
        nil
    }

    @objc func returnsBool() -> Bool {
        false
    }

    @objc func takesBlock(_ block: @escaping () -> Void) {}
    @objc func takesObject(_ object: NSObject?) {}
    @objc func takesObject(_ object: NSObject?, andBlock block: @escaping () -> Void) {}
    @objc class func classReturnsObject() -> NSObject? {
        nil
    }

    @objc var objectProperty: NSData?
    @objc var boolProperty: Bool { true }
}

class ObjCMethodContractTests: XCTestCase {
    private let fixture: AnyClass = SignatureFixture.self

    private func contract(_ name: String, _ kind: ObjCMethodContract.Kind = .instance, returns: ObjCType, arguments: [ObjCType] = []) -> ObjCMethodContract {
        ObjCMethodContract(NSSelectorFromString(name), kind, returns: returns, arguments: arguments)
    }

    func test_isSatisfied_givenMatchingSignatures_expectTrue() {
        XCTAssertTrue(contract("returnsNothing", returns: .void).isSatisfied(by: fixture))
        XCTAssertTrue(contract("returnsObject", returns: .object).isSatisfied(by: fixture))
        XCTAssertTrue(contract("returnsBool", returns: .bool).isSatisfied(by: fixture))
        XCTAssertTrue(contract("takesBlock:", returns: .void, arguments: [.block]).isSatisfied(by: fixture))
        XCTAssertTrue(contract("takesObject:", returns: .void, arguments: [.object]).isSatisfied(by: fixture))
        XCTAssertTrue(contract("takesObject:andBlock:", returns: .void, arguments: [.object, .block]).isSatisfied(by: fixture))
        XCTAssertTrue(contract("classReturnsObject", .class, returns: .object).isSatisfied(by: fixture))
        XCTAssertTrue(contract("objectProperty", returns: .object).isSatisfied(by: fixture))
        XCTAssertTrue(contract("setObjectProperty:", returns: .void, arguments: [.object]).isSatisfied(by: fixture))
        XCTAssertTrue(contract("boolProperty", returns: .bool).isSatisfied(by: fixture))
    }

    func test_isSatisfied_givenMissingSelector_expectFalse() {
        XCTAssertFalse(contract("doesNotExist", returns: .void).isSatisfied(by: fixture))
    }

    func test_isSatisfied_givenDifferentReturnType_expectFalse() {
        XCTAssertFalse(contract("returnsBool", returns: .object).isSatisfied(by: fixture))
        XCTAssertFalse(contract("returnsObject", returns: .void).isSatisfied(by: fixture))
        XCTAssertFalse(contract("returnsNothing", returns: .bool).isSatisfied(by: fixture))
    }

    func test_isSatisfied_givenDifferentArgumentType_expectFalse() {
        // An object where a block is expected: same selector shape, different ABI.
        XCTAssertFalse(contract("takesObject:", returns: .void, arguments: [.block]).isSatisfied(by: fixture))
        XCTAssertFalse(contract("takesBlock:", returns: .void, arguments: [.object]).isSatisfied(by: fixture))
    }

    func test_isSatisfied_givenDifferentArgumentCount_expectFalse() {
        XCTAssertFalse(contract("takesObject:", returns: .void, arguments: [.object, .object]).isSatisfied(by: fixture))
        XCTAssertFalse(contract("takesObject:andBlock:", returns: .void, arguments: [.object]).isSatisfied(by: fixture))
    }

    func test_isSatisfied_givenInstanceMethodCheckedAsClassMethod_expectFalse() {
        XCTAssertFalse(contract("returnsObject", .class, returns: .object).isSatisfied(by: fixture))
        XCTAssertFalse(contract("classReturnsObject", returns: .object).isSatisfied(by: fixture))
    }

    func test_unsatisfied_expectOnlyFailingContracts() {
        let contracts = [
            contract("returnsNothing", returns: .void),
            contract("takesObject:", returns: .void, arguments: [.block])
        ]

        let unsatisfied = contracts.unsatisfied(by: fixture)

        XCTAssertEqual(unsatisfied.map { NSStringFromSelector($0.selector) }, ["takesObject:"])
    }
}
