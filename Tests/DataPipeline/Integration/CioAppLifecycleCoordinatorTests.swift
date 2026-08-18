import UIKit
import XCTest

@testable import CioDataPipelines
@testable import CioInternalCommonMocks

@MainActor
final class CioLifecycleCoordinatorsTests: XCTestCase {
    private let logger = LoggerMock()
    private let url = URL(string: "myapp://settings")!

    func testAppDelegateHandleOpenURL_givenCallback_thenRoutesOnce() {
        let coordinator = CioAppDelegateLifecycleCoordinator()
        var receivedURLs: [URL] = []

        let options: [UIApplication.OpenURLOptionsKey: Any] = [.openInPlace: true]
        var receivedOptions: [UIApplication.OpenURLOptionsKey: Any] = [:]
        let result = coordinator.handleOpenURL(url, options: options) { receivedURL, routeOptions in
            receivedURLs.append(receivedURL)
            receivedOptions = routeOptions
            return true
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(receivedURLs, [url])
        XCTAssertEqual(receivedOptions[.openInPlace] as? Bool, true)
    }

    func testAppDelegateHandleOpenURL_givenRepeatedIdenticalURL_thenTreatsEachAsNewOccurrence() {
        let coordinator = CioAppDelegateLifecycleCoordinator()
        var routeCount = 0

        for _ in 0 ..< 2 {
            XCTAssertEqual(
                coordinator.handleOpenURL(url, options: [:]) { _, _ in
                    routeCount += 1
                    return true
                },
                .handled
            )
        }

        XCTAssertEqual(routeCount, 2)
    }

    func testAppDelegateHandleUserActivity_givenCallback_thenReturnsHostResult() {
        let coordinator = CioAppDelegateLifecycleCoordinator()
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        var receivedActivity: NSUserActivity?

        let result = coordinator.handleUserActivity(activity) { value in
            receivedActivity = value
            return false
        }

        XCTAssertEqual(result, .unhandled)
        XCTAssertTrue(receivedActivity === activity)
    }

    func testAppDelegateHandleShortcut_givenRouteCompletes_thenCompletionRunsExactlyOnce() {
        let coordinator = CioAppDelegateLifecycleCoordinator()
        let shortcut = makeShortcut()
        var routeCount = 0
        var completionValues: [Bool] = []

        coordinator.handleShortcut(
            shortcut,
            route: { _ in
                routeCount += 1
                return true
            },
            completionHandler: { completionValues.append($0) }
        )

        XCTAssertEqual(routeCount, 1)
        XCTAssertEqual(completionValues, [true])
    }

    func testAppDelegateHandleShortcut_givenRouteDeclines_thenCompletionRunsExactlyOnce() {
        let coordinator = CioAppDelegateLifecycleCoordinator()
        var routeCount = 0
        var completionValues: [Bool] = []

        let result = coordinator.handleShortcut(
            makeShortcut(),
            route: { _ in
                routeCount += 1
                return false
            },
            completionHandler: { completionValues.append($0) }
        )

        XCTAssertEqual(result, .unhandled)
        XCTAssertEqual(routeCount, 1)
        XCTAssertEqual(completionValues, [false])
    }

    func testSceneHandleConnection_givenNoActivation_thenReturnsNoActivation() {
        let coordinator = makeSceneCoordinator()
        var routeCount = 0

        let result = handleConnection(coordinator, routeCount: &routeCount)

        XCTAssertEqual(result, .noActivation)
        XCTAssertEqual(routeCount, 0)
    }

    func testSceneHandleConnection_givenOneURL_thenRoutesExactlyOnce() {
        let coordinator = makeSceneCoordinator()
        var routeCount = 0

        let result = handleConnection(coordinator, urls: [url], routeCount: &routeCount)

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(routeCount, 1)
    }

    func testSceneHandleConnection_givenOneUserActivity_thenRoutesExactlyOnce() {
        let coordinator = makeSceneCoordinator()
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        var receivedActivity: NSUserActivity?

        let result = coordinator.handleConnection(
            makeSceneActivation(userActivities: [activity]),
            routeURL: { _ in
                XCTFail("Unexpected URL route")
                return false
            },
            continueUserActivity: { value in
                receivedActivity = value
                return true
            },
            performShortcut: { _ in
                XCTFail("Unexpected shortcut route")
                return false
            }
        )

        XCTAssertEqual(result, .handled)
        XCTAssertTrue(receivedActivity === activity)
    }

    func testSceneHandleConnection_givenOneShortcut_thenRoutesExactlyOnce() {
        let coordinator = makeSceneCoordinator()
        let shortcut = makeShortcut()
        var receivedShortcut: UIApplicationShortcutItem?

        let result = coordinator.handleConnection(
            makeSceneActivation(shortcutItem: shortcut),
            routeURL: { _ in
                XCTFail("Unexpected URL route")
                return false
            },
            continueUserActivity: { _ in
                XCTFail("Unexpected user-activity route")
                return false
            },
            performShortcut: { value in
                receivedShortcut = value
                return true
            }
        )

        XCTAssertEqual(result, .handled)
        XCTAssertTrue(receivedShortcut === shortcut)
    }

    func testSceneHandleConnection_givenNotificationResponse_thenLeavesItApplicationOwned() {
        let coordinator = makeSceneCoordinator()
        var routeCount = 0

        let result = handleConnection(
            coordinator,
            hasNotificationResponse: true,
            routeCount: &routeCount
        )

        XCTAssertEqual(result, .notificationOwnedByApplication)
        XCTAssertEqual(routeCount, 0)
    }

    func testSceneHandleConnection_givenNotificationAndURL_thenRejectsAndLogs() {
        let coordinator = makeSceneCoordinator()
        var routeCount = 0

        let result = handleConnection(
            coordinator,
            urls: [url],
            hasNotificationResponse: true,
            routeCount: &routeCount
        )

        XCTAssertEqual(result, .rejectedAmbiguousInput)
        XCTAssertEqual(routeCount, 0)
        XCTAssertEqual(logger.errorCallsCount, 1)
    }

    func testSceneHandleConnection_givenMultipleURLs_thenRejectsWithoutRouting() {
        let coordinator = makeSceneCoordinator()
        let secondURL = URL(string: "myapp://dashboard")!
        var routeCount = 0

        let result = handleConnection(
            coordinator,
            urls: [url, secondURL],
            routeCount: &routeCount
        )

        XCTAssertEqual(result, .rejectedAmbiguousInput)
        XCTAssertEqual(routeCount, 0)
        XCTAssertEqual(logger.errorCallsCount, 1)
    }

    func testSceneHandleConnection_givenMultipleUserActivities_thenRejectsWithoutRouting() {
        let coordinator = makeSceneCoordinator()
        let firstActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        let secondActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        var routeCount = 0

        let result = coordinator.handleConnection(
            makeSceneActivation(userActivities: [firstActivity, secondActivity]),
            routeURL: { _ in routeCount += 1
                return true
            },
            continueUserActivity: { _ in routeCount += 1
                return true
            },
            performShortcut: { _ in routeCount += 1
                return true
            }
        )

        XCTAssertEqual(result, .rejectedAmbiguousInput)
        XCTAssertEqual(routeCount, 0)
    }

    func testSceneHandleConnection_givenURLAndUserActivity_thenRejectsWithoutRouting() {
        let coordinator = makeSceneCoordinator()
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        var routeCount = 0

        let result = coordinator.handleConnection(
            makeSceneActivation(urls: [url], userActivities: [activity]),
            routeURL: { _ in routeCount += 1
                return true
            },
            continueUserActivity: { _ in routeCount += 1
                return true
            },
            performShortcut: { _ in routeCount += 1
                return true
            }
        )

        XCTAssertEqual(result, .rejectedAmbiguousInput)
        XCTAssertEqual(routeCount, 0)
    }

    func testSceneHandleConnection_givenRepeatedIdenticalURL_thenRoutesNewOccurrences() {
        let coordinator = makeSceneCoordinator()
        var routeCount = 0

        for _ in 0 ..< 2 {
            XCTAssertEqual(
                handleConnection(coordinator, urls: [url], routeCount: &routeCount),
                .handled
            )
        }

        XCTAssertEqual(routeCount, 2)
    }

    func testSceneHandleOpenURLs_givenOneURL_thenRoutesExactlyOnce() {
        let coordinator = makeSceneCoordinator()
        var receivedURLs: [URL] = []

        let result = coordinator.handleOpenURLs([url]) { receivedURL in
            receivedURLs.append(receivedURL)
            return true
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(receivedURLs, [url])
    }

    func testSceneHandleOpenURLs_givenNoURL_thenReturnsNoActivationWithoutRouting() {
        let coordinator = makeSceneCoordinator()
        var routeCount = 0

        let result = coordinator.handleOpenURLs([]) { _ in
            routeCount += 1
            return true
        }

        XCTAssertEqual(result, .noActivation)
        XCTAssertEqual(routeCount, 0)
    }

    func testSceneHandleOpenURLs_givenMultipleURLs_thenRoutesEveryURL() {
        let coordinator = makeSceneCoordinator()
        let secondURL = URL(string: "myapp://dashboard")!
        var receivedURLs: [URL] = []

        let result = coordinator.handleOpenURLs([url, secondURL]) { receivedURL in
            receivedURLs.append(receivedURL)
            return true
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(receivedURLs, [url, secondURL])
        XCTAssertEqual(logger.errorCallsCount, 0)
    }

    func testSceneHandleOpenURLs_givenMixedRouteResults_thenRoutesEveryURLAndReturnsHandled() {
        let coordinator = makeSceneCoordinator()
        let secondURL = URL(string: "myapp://dashboard")!
        var receivedURLs: [URL] = []

        let result = coordinator.handleOpenURLs([url, secondURL]) { receivedURL in
            receivedURLs.append(receivedURL)
            return receivedURL == secondURL
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(receivedURLs, [url, secondURL])
    }

    func testSceneHandleOpenURLs_givenEveryRouteDeclines_thenReturnsUnhandled() {
        let coordinator = makeSceneCoordinator()
        let secondURL = URL(string: "myapp://dashboard")!
        var routeCount = 0

        let result = coordinator.handleOpenURLs([url, secondURL]) { _ in
            routeCount += 1
            return false
        }

        XCTAssertEqual(result, .unhandled)
        XCTAssertEqual(routeCount, 2)
    }

    func testSceneHandleUserActivity_givenCallback_thenRoutesExactlyOnce() {
        let coordinator = makeSceneCoordinator()
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        var routeCount = 0

        let result = coordinator.handleUserActivity(activity) { receivedActivity in
            routeCount += 1
            return receivedActivity === activity
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(routeCount, 1)
    }

    func testSceneHandleShortcut_givenRouteDeclines_thenCompletesFalseExactlyOnce() {
        let coordinator = makeSceneCoordinator()
        var routeCount = 0
        var completionValues: [Bool] = []

        coordinator.handleShortcut(
            makeShortcut(),
            route: { _ in routeCount += 1
                return false
            },
            completionHandler: { completionValues.append($0) }
        )

        XCTAssertEqual(routeCount, 1)
        XCTAssertEqual(completionValues, [false])
    }

    func testSceneHandleShortcut_givenRouteCompletes_thenCompletesTrueExactlyOnce() {
        let coordinator = makeSceneCoordinator()
        var routeCount = 0
        var completionValues: [Bool] = []

        let result = coordinator.handleShortcut(
            makeShortcut(),
            route: { _ in
                routeCount += 1
                return true
            },
            completionHandler: { completionValues.append($0) }
        )

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(routeCount, 1)
        XCTAssertEqual(completionValues, [true])
    }

    func testSwiftUIHandleOpenURL_givenRepeatedURL_thenRoutesRepeatedOccurrences() {
        let coordinator = CioSwiftUILifecycleCoordinator()
        var routeCount = 0

        for _ in 0 ..< 2 {
            XCTAssertEqual(
                coordinator.handleOpenURL(url) { _ in
                    routeCount += 1
                    return true
                },
                .handled
            )
        }

        XCTAssertEqual(routeCount, 2)
    }

    private func makeSceneCoordinator() -> CioSceneLifecycleCoordinator {
        CioSceneLifecycleCoordinator(logger: logger)
    }

    private func makeShortcut() -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(type: "settings", localizedTitle: "Settings")
    }

    private func handleConnection(
        _ coordinator: CioSceneLifecycleCoordinator,
        urls: [URL] = [],
        hasNotificationResponse: Bool = false,
        routeCount: inout Int
    ) -> CioAppLifecycleHandlingResult {
        coordinator.handleConnection(
            makeSceneActivation(
                urls: urls,
                hasNotificationResponse: hasNotificationResponse
            ),
            routeURL: { _ in routeCount += 1
                return true
            },
            continueUserActivity: { _ in routeCount += 1
                return true
            },
            performShortcut: { _ in routeCount += 1
                return true
            }
        )
    }

    private func makeSceneActivation(
        urls: [URL] = [],
        userActivities: [NSUserActivity] = [],
        shortcutItem: UIApplicationShortcutItem? = nil,
        hasNotificationResponse: Bool = false
    ) -> CioSceneLifecycleCoordinator.SceneConnectionActivation<URL> {
        CioSceneLifecycleCoordinator.SceneConnectionActivation(
            urlActivations: urls,
            userActivities: userActivities,
            shortcutItem: shortcutItem,
            hasNotificationResponse: hasNotificationResponse
        )
    }
}
