@testable import CioInternalCommon
@testable import CioInternalCommonMocks
import Foundation
import SharedTests
import XCTest

class LogLevelStoreTest: UnitTest {
    private let systemLoggerMock = SystemLoggerMock()
    private var store: CioLogLevelStore!

    override func setUp() {
        super.setUp()

        mockCollection.add(mock: systemLoggerMock)
        store = CioLogLevelStore(keyValueStorage: InMemorySharedKeyValueStorage())
    }

    // MARK: store

    func test_logLevel_givenNeverSaved_expectNil() {
        XCTAssertNil(store.logLevel)
    }

    func test_saveLogLevel_expectReadBack() {
        store.saveLogLevel(.debug)

        XCTAssertEqual(store.logLevel, .debug)
    }

    // MARK: logger

    func test_newLogger_givenSavedLevel_expectSavedLevelUsedBeforeAppSetsOne() {
        store.saveLogLevel(.debug)

        let logger = LoggerImpl(logger: systemLoggerMock, logLevelStore: store)
        logger.debug("cold start", "Push")

        XCTAssertEqual(logger.logLevel, .debug)
        XCTAssertEqual(systemLoggerMock.logReceivedArguments?.message, "[Push] cold start")
    }

    func test_newLogger_givenNothingSaved_expectDefaultLevel() {
        let logger = LoggerImpl(logger: systemLoggerMock, logLevelStore: store)

        XCTAssertEqual(logger.logLevel, .error)
    }

    func test_setLogLevel_givenSavedLevel_expectAppLevelWinsImmediately() {
        store.saveLogLevel(.debug)
        let logger = LoggerImpl(logger: systemLoggerMock, logLevelStore: store)

        logger.setLogLevel(.none)
        logger.debug("dropped", nil)

        XCTAssertEqual(logger.logLevel, CioLogLevel.none)
        XCTAssertFalse(systemLoggerMock.logCalled)
    }

    /// The NSE (and Live Activities) set their level only through `setLogLevel`, so they can't replace the app's.
    func test_setLogLevel_expectSavedLevelUnchanged() {
        store.saveLogLevel(.debug)
        let logger = LoggerImpl(logger: systemLoggerMock, logLevelStore: store)

        logger.setLogLevel(.error)

        XCTAssertEqual(store.logLevel, .debug)
    }

    /// The suite is named after the process's bundle id, so an app extension's store is not the app's.
    func test_saveLogLevel_givenExtensionBundleId_expectAppLevelUntouched() {
        let appBundleId = "io.customer.loglevel-test.\(UUID().uuidString)"
        let extensionBundleId = "\(appBundleId).NotificationService"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: "io.customer.sdk.\(appBundleId).shared")
            UserDefaults.standard.removePersistentDomain(forName: "io.customer.sdk.\(extensionBundleId).shared")
        }
        let appStore = makeUserDefaultsStore(bundleId: appBundleId)
        let extensionStore = makeUserDefaultsStore(bundleId: extensionBundleId)

        appStore.saveLogLevel(.debug)
        extensionStore.saveLogLevel(.none)

        XCTAssertEqual(appStore.logLevel, .debug)
        XCTAssertEqual(extensionStore.logLevel, CioLogLevel.none)
    }

    private func makeUserDefaultsStore(bundleId: String) -> CioLogLevelStore {
        let deviceMetricsGrabber = DeviceMetricsGrabberMock()
        deviceMetricsGrabber.underlyingAppBundleId = bundleId
        return CioLogLevelStore(keyValueStorage: UserDefaultsSharedKeyValueStorage(deviceMetricsGrabber: deviceMetricsGrabber))
    }
}
