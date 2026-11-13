@testable import CioDataPipelines
import Foundation
import XCTest

class ApnsEnvironmentProviderTest: XCTestCase {
    func test_environment_givenSimulator_expectSandbox() {
        XCTAssertEqual(resolve(isSimulator: true, profile: nil), .sandbox)
        XCTAssertEqual(resolve(isSimulator: true, profile: profile(apsEnvironment: "production")), .sandbox)
    }

    func test_environment_givenDeviceWithoutProfile_expectProduction() {
        XCTAssertEqual(resolve(profile: nil), .production)
    }

    func test_environment_givenMacWithoutProfile_expectNil() {
        XCTAssertNil(resolve(isRunningOnMac: true, profile: nil))
    }

    func test_environment_givenDevelopmentProfile_expectSandbox() {
        XCTAssertEqual(resolve(profile: profile(apsEnvironment: "development")), .sandbox)
        XCTAssertEqual(resolve(isRunningOnMac: true, profile: profile(apsEnvironment: "development")), .sandbox)
    }

    func test_environment_givenProductionProfile_expectProduction() {
        XCTAssertEqual(resolve(profile: profile(apsEnvironment: "production")), .production)
    }

    func test_environment_givenProfileWithoutPush_expectNil() {
        XCTAssertNil(resolve(profile: profile(apsEnvironment: nil)))
    }

    func test_environment_givenUnknownApsEnvironment_expectNil() {
        XCTAssertNil(resolve(profile: profile(apsEnvironment: "staging")))
    }

    func test_environment_givenUnusableProfile_expectNil() {
        XCTAssertNil(SdkApnsEnvironmentProvider.environment(isSimulator: false, isRunningOnMac: false, profile: .unusable))
        XCTAssertNil(SdkApnsEnvironmentProvider.environment(isSimulator: false, isRunningOnMac: true, profile: .unusable))
    }

    func test_environment_givenProfileLargerThanLimit_expectNil() {
        var givenProfile = profile(apsEnvironment: "production")
        givenProfile.append(Data(count: SdkApnsEnvironmentProvider.maxProfileSize))

        XCTAssertNil(resolve(profile: givenProfile))
    }

    func test_environment_givenProfileAtLimit_expectValue() {
        var givenProfile = profile(apsEnvironment: "production")
        givenProfile.append(Data(count: SdkApnsEnvironmentProvider.maxProfileSize - givenProfile.count))

        XCTAssertEqual(resolve(profile: givenProfile), .production)
    }

    func test_readProfile_givenNoUrl_expectMissing() {
        XCTAssertEqual(SdkApnsEnvironmentProvider.readProfile(at: nil), .missing)
    }

    func test_readProfile_givenFile_expectContents() throws {
        let givenData = profile(apsEnvironment: "development")
        let url = try temporaryFile(givenData)

        XCTAssertEqual(SdkApnsEnvironmentProvider.readProfile(at: url), .contents(givenData))
    }

    func test_readProfile_givenFileAtLimit_expectContents() throws {
        let givenData = Data(count: SdkApnsEnvironmentProvider.maxProfileSize)
        let url = try temporaryFile(givenData)

        XCTAssertEqual(SdkApnsEnvironmentProvider.readProfile(at: url), .contents(givenData))
    }

    func test_readProfile_givenFileLargerThanLimit_expectUnusable() throws {
        let url = try temporaryFile(Data(count: SdkApnsEnvironmentProvider.maxProfileSize + 1))

        XCTAssertEqual(SdkApnsEnvironmentProvider.readProfile(at: url), .unusable)
    }

    func test_readProfile_givenMissingFileOrDirectory_expectUnusable() {
        let missingFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        XCTAssertEqual(SdkApnsEnvironmentProvider.readProfile(at: missingFile), .unusable)
        XCTAssertEqual(SdkApnsEnvironmentProvider.readProfile(at: FileManager.default.temporaryDirectory), .unusable)
    }

    func test_environment_givenGarbageProfile_expectNil() {
        XCTAssertNil(resolve(profile: Data()))
        XCTAssertNil(resolve(profile: Data([0x30, 0x80, 0x06, 0x09, 0x2A, 0x86])))
        XCTAssertNil(resolve(profile: Data("<?xml version=\"1.0\"?><plist><dict>".utf8)))
    }

    func test_environment_givenApsEnvironmentOutsideEntitlements_expectNil() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>aps-environment</key><string>production</string></dict></plist>
        """
        XCTAssertNil(resolve(profile: signedEnvelope(around: plist)))
    }

    func test_environment_givenApsEnvironmentBeforeEntitlements_expectNil() {
        let plist = """
        <?xml version="1.0"?><plist><dict><key>aps-environment</key><string>production</string>
        <key>Entitlements</key><dict><key>get-task-allow</key><true/></dict></dict></plist>
        """
        XCTAssertNil(resolve(profile: signedEnvelope(around: plist)))
    }

    func test_environment_givenWhitespaceBetweenKeyAndValue_expectValue() {
        let plist = "<plist><dict><key>Entitlements</key><dict><key>aps-environment</key>\n\t\t\r <string>development</string></dict></dict></plist>"

        XCTAssertEqual(resolve(profile: signedEnvelope(around: plist)), .sandbox)
    }

    func test_environment_givenMalformedPlist_expectNil() {
        let cases = [
            // Markers out of order, or cut off
            "</plist><?xml version=\"1.0\"?>",
            "garbage<?xml",
            "<key>Entitlements</key><dict><key>aps-environment</key><string>production",
            "<key>Entitlements</key><dict><key>aps-environment</key>",
            "</string><key>Entitlements</key><key>aps-environment</key>",
            // Something other than whitespace between the key and its value
            "<key>Entitlements</key><dict><key>aps-environment</key><true/><string>production</string>",
            // Root or values of unexpected types
            "<?xml version=\"1.0\"?><plist><array><string>production</string></array></plist>",
            "<?xml version=\"1.0\"?><plist><dict><key>Entitlements</key><array/></dict></plist>",
            "<?xml version=\"1.0\"?><plist><dict><key>Entitlements</key><dict><key>aps-environment</key><integer>1</integer></dict></dict></plist>"
        ]
        for givenCase in cases {
            XCTAssertNil(resolve(profile: signedEnvelope(around: givenCase)), givenCase)
        }

        var invalidUtf8 = signedEnvelope(around: "<?xml version=\"1.0\"?><plist><dict><key>Entitlements</key><dict><key>aps-environment</key><string>")
        invalidUtf8.append(contentsOf: [0xFF, 0xFE, 0xC3])
        invalidUtf8.append(Data("</string></dict></dict></plist>".utf8))
        XCTAssertNil(resolve(profile: invalidUtf8))
    }

    // A truncated profile must never crash, only resolve to nil or the full profile's value
    func test_environment_givenEveryTruncationOfProfile_expectNoCrash() {
        let givenProfile = profile(apsEnvironment: "production")

        for length in 0 ... givenProfile.count {
            let actual = resolve(profile: givenProfile.prefix(length))
            XCTAssertTrue(actual == nil || actual == .production, "length: \(length)")
        }
    }

    // Data slices keep their parent's indices, so offsets must come from the data itself
    func test_environment_givenSliceNotStartingAtZero_expectSameResult() {
        let givenProfile = profile(apsEnvironment: "production")

        // Any start before the Entitlements key keeps the value readable
        for start in [1, 10, 17, 40] {
            XCTAssertEqual(resolve(profile: givenProfile.suffix(from: start)), .production, "start: \(start)")
        }
    }

    func test_environment_givenRandomBytes_expectNoCrash() {
        var generator = SeededGenerator(seed: 2770)
        let markers = ["<key>Entitlements</key>", "<key>aps-environment</key>", "<string>", "production", "</string>"].map { Data($0.utf8) }

        for _ in 0 ..< 500 {
            var givenData = Data((0 ..< Int.random(in: 0 ... 256, using: &generator)).map { _ in UInt8.random(in: 0 ... 255, using: &generator) })
            for marker in markers where Bool.random(using: &generator) {
                givenData.insert(contentsOf: marker, at: Int.random(in: 0 ... givenData.count, using: &generator))
            }

            _ = resolve(profile: givenData)
        }
    }

    // Markers in order with random filler between them, so the search often reaches the value
    func test_environment_givenOrderedMarkersWithRandomFiller_expectOnlyKnownValues() {
        var generator = SeededGenerator(seed: 1395)
        let markers = ["<key>Entitlements</key>", "<key>aps-environment</key>", "<string>", "production", "</string>"].map { Data($0.utf8) }
        let fillers = [Data(), Data(" ".utf8), Data("\n\t".utf8), Data("<x>".utf8)]

        var productionCount = 0
        for _ in 0 ..< 500 {
            var givenData = Data()
            for marker in markers {
                givenData.append(fillers.randomElement(using: &generator) ?? Data())
                if Int.random(in: 0 ..< 10, using: &generator) > 0 {
                    givenData.append(marker)
                }
            }

            let actual = resolve(profile: givenData)
            XCTAssertTrue(actual == nil || actual == .production)
            if actual == .production {
                productionCount += 1
            }
        }
        XCTAssertGreaterThan(productionCount, 0, "the value path must be reached")
    }

    func test_environment_expectRawValuesSentAsAttribute() {
        XCTAssertEqual(ApnsEnvironment.sandbox.rawValue, "sandbox")
        XCTAssertEqual(ApnsEnvironment.production.rawValue, "production")
    }
}

private extension ApnsEnvironmentProviderTest {
    func resolve(isSimulator: Bool = false, isRunningOnMac: Bool = false, profile: Data?) -> ApnsEnvironment? {
        SdkApnsEnvironmentProvider.environment(
            isSimulator: isSimulator,
            isRunningOnMac: isRunningOnMac,
            profile: profile.map { .contents($0) } ?? .missing
        )
    }

    // Shaped like embedded.mobileprovision: binary CMS bytes around a plist with top-level keys before Entitlements
    func profile(apsEnvironment: String?) -> Data {
        let apsEntry = apsEnvironment.map { "<key>aps-environment</key><string>\($0)</string>" } ?? ""
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AppIDName</key><string>Sample</string>
            <key>DeveloperCertificates</key><array><data>MIIFxzCCBK+gAwIBAgIQ</data></array>
            <key>Entitlements</key>
            <dict>
                <key>application-identifier</key><string>TEAMID.io.customer.sample</string>
                \(apsEntry)
                <key>get-task-allow</key><true/>
            </dict>
            <key>Name</key><string>Sample Profile</string>
        </dict>
        </plist>
        """
        return signedEnvelope(around: plist)
    }

    func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        return url
    }

    // Deterministic, so a failure reproduces
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        init(seed: UInt64) {
            self.state = seed
        }

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    func signedEnvelope(around plist: String) -> Data {
        var data = Data([0x30, 0x80, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02, 0xA0, 0x80, 0x00, 0xFF])
        data.append(Data(plist.utf8))
        data.append(Data([0x00, 0x00, 0xA0, 0x82, 0x0B, 0xFE, 0x3C, 0x2F, 0x70, 0xFF, 0x00]))
        return data
    }
}
