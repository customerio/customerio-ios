@testable import CioAnalytics
@testable import CioDataPipelinesMocks
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import SharedTests
import XCTest

class DataPipelinePushEnabledRefreshTests: IntegrationTest {
    private var outputReader: OutputReaderPlugin!

    private let deviceAttributesMock = DeviceAttributesProviderMock()
    // Counts device updates requested, including those made while the SDK initializes
    private let deviceUpdateRequests = Synchronized(0)
    // When set, attribute reads finish only when the test runs them, as reads are async in the app
    private let defersDeviceAttributes = Synchronized(false)
    private let pendingDeviceAttributes = Synchronized<[() -> Void]>([])
    private var pushSubscribedAtLaunch = false

    override func setUpDependencies() {
        super.setUpDependencies()

        mockCollection.add(mocks: [deviceAttributesMock])

        let deviceInfo: DeviceInfoStub = deviceInfoStub
        deviceInfo.pushSubscribed = pushSubscribedAtLaunch
        let requests = deviceUpdateRequests
        let defers = defersDeviceAttributes
        let pending = pendingDeviceAttributes
        deviceAttributesMock.getDefaultDeviceAttributesClosure = { onComplete in
            requests.mutating { $0 += 1 }
            deviceInfo.isPushSubscribed { isEnabled in
                let complete = { onComplete(["push_enabled": String(isEnabled)]) }
                if defers.wrappedValue {
                    pending.mutating { $0.append(complete) }
                } else {
                    complete()
                }
            }
        }
        diGraphShared.override(value: deviceAttributesMock, forType: DeviceAttributesProvider.self)
    }

    override func setUp() {
        // Each test calls setUpSdk(), as some set stored data or config before the SDK initializes
    }

    private func setUpSdk(autoTrackDeviceAttributes: Bool = true, pushSubscribed: Bool = false, identified: Bool = true) {
        pushSubscribedAtLaunch = pushSubscribed
        super.setUp(modifySdkConfig: { config in
            config.autoTrackDeviceAttributes(autoTrackDeviceAttributes)
        })
        outputReader = (customerIO.add(plugin: OutputReaderPlugin()) as? OutputReaderPlugin)
        if identified {
            customerIO.identify(userId: String.random)
        }
    }

    // Same route the lifecycle monitor uses to reach plugins
    private func simulateAppBecameActive() {
        analytics.apply { plugin in
            (plugin as? iOSLifecycle)?.applicationDidBecomeActive(application: nil)
        }
    }

    // Stores a token without the SDK sending a device update for it
    private func storeDeviceToken(_ token: String) {
        var globalDataStore = diGraphShared.globalDataStore
        globalDataStore.pushDeviceToken = token
    }

    private var lastPushEnabledSent: String? {
        let properties = outputReader.deviceUpdateEvents.last?.properties?.dictionaryValue
        return properties?["push_enabled"] as? String
    }

    // MARK: - App becomes active

    func test_becomeActive_givenPushEnabledChanged_expectDeviceUpdateWithNewValue() {
        setUpSdk()
        let givenToken = String.random
        customerIO.registerDeviceToken(givenToken)
        outputReader.resetPlugin()

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()

        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 1)
        XCTAssertEqual(outputReader.deviceUpdateEvents.last?.deviceToken, givenToken)
        XCTAssertEqual(lastPushEnabledSent, "true")
    }

    func test_becomeActive_givenPushEnabledUnchanged_expectNoDeviceUpdate() {
        setUpSdk()
        customerIO.registerDeviceToken(String.random)
        outputReader.resetPlugin()

        simulateAppBecameActive()

        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 0)
    }

    func test_becomeActive_givenPushEnabledChangedBackAndForth_expectDeviceUpdateForEachChange() {
        setUpSdk()
        customerIO.registerDeviceToken(String.random)
        outputReader.resetPlugin()

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()
        simulateAppBecameActive()
        deviceInfoStub.pushSubscribed = false
        simulateAppBecameActive()

        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 2)
        XCTAssertEqual(lastPushEnabledSent, "false")
    }

    func test_becomeActive_givenNoDeviceToken_expectNoPermissionCheck() {
        setUpSdk()
        let checksAfterSetUp = deviceInfoStub.isPushSubscribedCallCount.wrappedValue

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()

        XCTAssertEqual(deviceInfoStub.isPushSubscribedCallCount.wrappedValue, checksAfterSetUp)
        XCTAssertEqual(deviceUpdateRequests.wrappedValue, 0)
    }

    func test_becomeActive_givenAutoTrackDeviceAttributesDisabled_expectNoDeviceUpdate() {
        setUpSdk(autoTrackDeviceAttributes: false)
        customerIO.registerDeviceToken(String.random)
        let requestsAfterRegister = deviceUpdateRequests.wrappedValue
        outputReader.resetPlugin()

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()

        XCTAssertNil(analytics.find(pluginType: CioDataPipelines.Context.self)?.onBecameActive.wrappedValue)
        XCTAssertEqual(deviceUpdateRequests.wrappedValue, requestsAfterRegister)
        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 0)
    }

    func test_becomeActive_givenValueSentByIdentify_expectNoDeviceUpdate() {
        setUpSdk(identified: false)
        customerIO.registerDeviceToken(String.random)
        deviceInfoStub.pushSubscribed = true
        // Sends the current value with the device for the new profile
        customerIO.identify(userId: String.random)
        outputReader.resetPlugin()

        simulateAppBecameActive()

        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 0)
    }

    func test_becomeActive_givenCustomPushEnabled_expectCustomValueKeptUntilPermissionChanges() {
        setUpSdk(pushSubscribed: true)
        customerIO.registerDeviceToken(String.random)
        customerIO.setDeviceAttributes(["push_enabled": "false"])
        XCTAssertEqual(lastPushEnabledSent, "false")
        outputReader.resetPlugin()

        simulateAppBecameActive()
        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 0)

        deviceInfoStub.pushSubscribed = false
        simulateAppBecameActive()
        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 1)
        XCTAssertEqual(lastPushEnabledSent, "false")
    }

    func test_becomeActive_givenCustomPushEnabledNotString_expectDeviceUpdateWhenPermissionChanges() {
        setUpSdk(pushSubscribed: true)
        customerIO.registerDeviceToken(String.random)
        customerIO.setDeviceAttributes(["push_enabled": false])
        outputReader.resetPlugin()

        simulateAppBecameActive()
        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 0)

        deviceInfoStub.pushSubscribed = false
        simulateAppBecameActive()
        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 1)
        XCTAssertEqual(lastPushEnabledSent, "false")
    }

    func test_becomeActive_givenNoDeviceUpdateSentYet_expectNoDeviceUpdate() {
        setUpSdk()
        storeDeviceToken(String.random)
        let requestsAfterSetUp = deviceUpdateRequests.wrappedValue

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()
        deviceInfoStub.pushSubscribed = false
        simulateAppBecameActive()

        XCTAssertEqual(deviceUpdateRequests.wrappedValue, requestsAfterSetUp)
    }

    func test_becomeActive_givenConcurrentChecksAfterChange_expectOneDeviceUpdate() throws {
        setUpSdk()
        customerIO.registerDeviceToken(String.random)
        let requestsAfterRegister = deviceUpdateRequests.wrappedValue
        // Called directly, as other lifecycle plugins aren't safe to call from many threads
        let plugin = try XCTUnwrap(analytics.find(pluginType: CioDataPipelines.Context.self))

        deviceInfoStub.pushSubscribed = true
        defersDeviceAttributes.wrappedValue = true
        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            plugin.applicationDidBecomeActive(application: nil)
        }
        defersDeviceAttributes.wrappedValue = false
        pendingDeviceAttributes.atomicSetAndFetch([]).forEach { $0() }

        XCTAssertEqual(deviceUpdateRequests.wrappedValue, requestsAfterRegister + 1)
        XCTAssertEqual(lastPushEnabledSent, "true")
    }

    func test_becomeActive_givenNoProfileIdentified_expectNoPermissionCheck() {
        setUpSdk(identified: false)
        customerIO.registerDeviceToken(String.random)
        let checksAfterRegister = deviceInfoStub.isPushSubscribedCallCount.wrappedValue
        outputReader.resetPlugin()

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()

        XCTAssertEqual(deviceInfoStub.isPushSubscribedCallCount.wrappedValue, checksAfterRegister)
        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 0)
    }

    func test_becomeActive_givenProfileCleared_expectNoDeviceUpdate() {
        setUpSdk()
        customerIO.registerDeviceToken(String.random)
        customerIO.clearIdentify()
        outputReader.resetPlugin()

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()

        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 0)
    }

    func test_becomeActive_givenProfileClearedWhilePermissionCheckPending_expectNoDeviceUpdate() {
        setUpSdk()
        customerIO.registerDeviceToken(String.random)
        // Still in flight when the profile is cleared, so it records a sent value again once it lands
        defersDeviceAttributes.wrappedValue = true
        customerIO.setDeviceAttributes(["plan": "basic"])
        deviceInfoStub.defersPushSubscribed.wrappedValue = true
        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()
        customerIO.clearIdentify()
        defersDeviceAttributes.wrappedValue = false
        pendingDeviceAttributes.atomicSetAndFetch([]).forEach { $0() }
        outputReader.resetPlugin()

        deviceInfoStub.defersPushSubscribed.wrappedValue = false
        deviceInfoStub.pendingPushSubscribed.atomicSetAndFetch([]).forEach { $0() }

        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 0)
    }

    func test_becomeActive_givenProfileIdentifiedAgainAfterClear_expectDeviceUpdateWithNewValue() {
        setUpSdk()
        customerIO.registerDeviceToken(String.random)
        customerIO.clearIdentify()
        customerIO.identify(userId: String.random)
        outputReader.resetPlugin()

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()

        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 1)
        XCTAssertEqual(lastPushEnabledSent, "true")
    }

    func test_becomeActive_givenDeviceDeleted_expectNoPermissionCheck() {
        setUpSdk()
        customerIO.registerDeviceToken(String.random)
        customerIO.deleteDeviceToken()
        let checksAfterDelete = deviceInfoStub.isPushSubscribedCallCount.wrappedValue
        outputReader.resetPlugin()

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()

        XCTAssertEqual(deviceInfoStub.isPushSubscribedCallCount.wrappedValue, checksAfterDelete)
        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 0)
    }

    func test_becomeActive_givenDeviceRegisteredAgainAfterDelete_expectDeviceUpdateWithNewValue() {
        setUpSdk()
        let givenToken = String.random
        customerIO.registerDeviceToken(givenToken)
        customerIO.deleteDeviceToken()
        customerIO.registerDeviceToken(givenToken)
        outputReader.resetPlugin()

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()

        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 1)
        XCTAssertEqual(lastPushEnabledSent, "true")
    }

    func test_becomeActive_givenDeviceAttributesSetAfterDelete_expectDeviceUpdateWithNewValue() {
        setUpSdk()
        customerIO.registerDeviceToken(String.random)
        customerIO.deleteDeviceToken()
        customerIO.setDeviceAttributes(["plan": "basic"])
        outputReader.resetPlugin()

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()

        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 1)
        XCTAssertEqual(lastPushEnabledSent, "true")
    }

    func test_becomeActive_givenProfileSwitched_expectDeviceUpdateWithNewValue() {
        setUpSdk()
        customerIO.registerDeviceToken(String.random)
        // Deletes the device from the previous profile and adds it to the new one
        customerIO.identify(userId: String.random)
        outputReader.resetPlugin()

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()

        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 1)
        XCTAssertEqual(lastPushEnabledSent, "true")
    }

    func test_becomeActive_givenTokenRefreshed_expectDeviceUpdateForNewToken() {
        setUpSdk()
        customerIO.registerDeviceToken(String.random)
        let givenNewToken = String.random
        customerIO.registerDeviceToken(givenNewToken)
        outputReader.resetPlugin()

        deviceInfoStub.pushSubscribed = true
        simulateAppBecameActive()

        XCTAssertEqual(outputReader.deviceUpdateEvents.count, 1)
        XCTAssertEqual(outputReader.deviceUpdateEvents.last?.deviceToken, givenNewToken)
        XCTAssertEqual(lastPushEnabledSent, "true")
    }

    // MARK: - App launches with a stored token

    func test_becomeActive_givenStoredTokenAtLaunch_expectNoDeviceUpdateUntilChange() {
        storeDeviceToken(String.random)

        setUpSdk(pushSubscribed: true)
        let requestsAfterLaunch = deviceUpdateRequests.wrappedValue
        XCTAssertGreaterThan(requestsAfterLaunch, 0)

        simulateAppBecameActive()
        XCTAssertEqual(deviceUpdateRequests.wrappedValue, requestsAfterLaunch)

        deviceInfoStub.pushSubscribed = false
        simulateAppBecameActive()
        XCTAssertEqual(deviceUpdateRequests.wrappedValue, requestsAfterLaunch + 1)
    }
}
