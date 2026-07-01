import Foundation
import Testing

@testable import CioLiveActivities

// MARK: - LiveActivityConfig defaults

struct LiveActivityConfigDefaultTests {
    @Test func defaultLogLevel_isNil() {
        let config = LiveActivityConfig()
        #expect(config.logLevel == nil)
    }

    @Test func defaultRegistrations_isEmpty() {
        let config = LiveActivityConfig()
        #expect(config.registrations.isEmpty)
    }

    @Test func defaultAppGroupIdentifier_isNil() {
        let config = LiveActivityConfig()
        #expect(config.appGroupIdentifier == nil)
    }

    @Test func defaultAssetRegistrations_isEmpty() {
        let config = LiveActivityConfig()
        #expect(config.assetRegistrations.isEmpty)
    }

    @Test func initWithLogLevel_setsLogLevel() {
        let config = LiveActivityConfig(logLevel: .debug)
        #expect(config.logLevel == .debug)
    }
}

// MARK: - LiveActivityConfigBuilder (iOS only)

#if os(iOS)
import ActivityKit
import CioLiveActivities_Attributes

@available(iOS 17.2, *)
private struct TestActivityAttributes: CIOActivityAttribute {
    struct ContentState: Codable, Hashable {
        var progress: Double
    }

    let activityInstanceId: String
}

@available(iOS 17.2, *)
private struct AnotherActivityAttributes: CIOActivityAttribute {
    struct ContentState: Codable, Hashable {
        var label: String
    }

    let activityInstanceId: String
}

struct LiveActivityConfigBuilderTests {
    @Test func defaultBuilder_hasNoRegistrations() {
        let config = LiveActivityConfigBuilder().build()
        #expect(config.registrations.isEmpty)
    }

    @Test func logLevelFluent_setsLogLevel() {
        let config = LiveActivityConfigBuilder()
            .logLevel(.error)
            .build()
        #expect(config.logLevel == .error)
    }

    @Test func appGroupFluent_setsIdentifier() {
        let config = LiveActivityConfigBuilder()
            .appGroup("group.io.customer.example")
            .build()
        #expect(config.appGroupIdentifier == "group.io.customer.example")
    }

    @Test func registerAsset_addsAssetRegistration() {
        let url = URL(fileURLWithPath: "/tmp/image.png")
        let config = LiveActivityConfigBuilder()
            .registerAsset("logo", at: url)
            .build()
        #expect(config.assetRegistrations.count == 1)
    }

    @Test func register_addsOneRegistration() {
        guard #available(iOS 17.2, *) else { return }
        let config = LiveActivityConfigBuilder()
            .register(TestActivityAttributes.self, identifier: "com.test.activity")
            .build()
        #expect(config.registrations.count == 1)
    }

    @Test func register_setsCorrectActivityIdentifier() {
        guard #available(iOS 17.2, *) else { return }
        let config = LiveActivityConfigBuilder()
            .register(TestActivityAttributes.self, identifier: "com.test.activity")
            .build()
        #expect(config.registrations[0].activityIdentifier == "com.test.activity")
    }

    @Test func registerMultiple_addsAllRegistrations() {
        guard #available(iOS 17.2, *) else { return }
        let config = LiveActivityConfigBuilder()
            .register(TestActivityAttributes.self, identifier: "com.test.activity")
            .register(AnotherActivityAttributes.self, identifier: "com.test.another")
            .build()
        #expect(config.registrations.count == 2)
    }

    @Test func registerMultiple_preservesDistinctIdentifiers() {
        guard #available(iOS 17.2, *) else { return }
        let config = LiveActivityConfigBuilder()
            .register(TestActivityAttributes.self, identifier: "com.test.activity")
            .register(AnotherActivityAttributes.self, identifier: "com.test.another")
            .build()
        let ids = Set(config.registrations.map(\.activityIdentifier))
        #expect(ids.contains("com.test.activity"))
        #expect(ids.contains("com.test.another"))
    }

    @Test func builderIsValueType_mutationsDoNotAlias() {
        let base = LiveActivityConfigBuilder()
        let withLog = base.logLevel(.debug)
        let baseConfig = base.build()
        let withLogConfig = withLog.build()
        #expect(baseConfig.logLevel == nil)
        #expect(withLogConfig.logLevel == .debug)
    }
}
#endif
