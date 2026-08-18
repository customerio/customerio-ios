import UIKit
import XCTest

@testable import CioDataPipelines
@testable import CioInternalCommonMocks

@MainActor
final class CioAppLifecycleCoordinatorTests: XCTestCase {
    private let logger = LoggerMock()
    private let url = URL(string: "myapp://settings")!

    func testHandleApplicationOpenURL_givenAppDelegateTopology_thenRoutesOnce() {
        let coordinator = makeCoordinator(.appDelegateOnly)
        var receivedURLs: [URL] = []

        let options: [UIApplication.OpenURLOptionsKey: Any] = [.openInPlace: true]
        var receivedOptions: [UIApplication.OpenURLOptionsKey: Any] = [:]
        let result = coordinator.handleApplicationOpenURL(url, options: options) { receivedURL, routeOptions in
            receivedURLs.append(receivedURL)
            receivedOptions = routeOptions
            return true
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(receivedURLs, [url])
        XCTAssertEqual(receivedOptions[.openInPlace] as? Bool, true)
    }

    func testHandleApplicationOpenURL_givenSceneTopology_thenRejectsAndLogs() {
        let coordinator = makeCoordinator(.uiScene)
        var routeCount = 0

        let result = coordinator.handleApplicationOpenURL(url, options: [:]) { _, _ in
            routeCount += 1
            return true
        }

        XCTAssertEqual(result, .rejectedHostTopology)
        XCTAssertEqual(routeCount, 0)
        XCTAssertEqual(logger.errorCallsCount, 1)
    }

    func testHandleApplicationOpenURL_givenRepeatedIdenticalURL_thenTreatsEachAsNewOccurrence() {
        let coordinator = makeCoordinator(.appDelegateOnly)
        var routeCount = 0

        for _ in 0 ..< 2 {
            XCTAssertEqual(
                coordinator.handleApplicationOpenURL(url, options: [:]) { _, _ in
                    routeCount += 1
                    return true
                },
                .handled
            )
        }

        XCTAssertEqual(routeCount, 2)
    }

    func testHandleApplicationUserActivity_givenAppDelegateTopology_thenReturnsHostResult() {
        let coordinator = makeCoordinator(.appDelegateOnly)
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        var receivedActivity: NSUserActivity?

        let result = coordinator.handleApplicationUserActivity(activity) { value in
            receivedActivity = value
            return false
        }

        XCTAssertEqual(result, .unhandled)
        XCTAssertTrue(receivedActivity === activity)
    }

    func testHandleApplicationUserActivity_givenSceneTopology_thenRejectsSdkSynthesizedSeat() {
        let coordinator = makeCoordinator(.uiScene)
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        var routeCount = 0

        let result = coordinator.handleApplicationUserActivity(activity) { _ in
            routeCount += 1
            return true
        }

        XCTAssertEqual(result, .rejectedHostTopology)
        XCTAssertEqual(routeCount, 0)
    }

    func testHandleApplicationShortcut_givenRouteCompletes_thenCompletionRunsExactlyOnce() {
        let coordinator = makeCoordinator(.appDelegateOnly)
        let shortcut = makeShortcut()
        var routeCount = 0
        var completionValues: [Bool] = []

        coordinator.handleApplicationShortcut(
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

    func testHandleApplicationShortcut_givenWrongTopology_thenCompletesFalseWithoutRouting() {
        let coordinator = makeCoordinator(.uiScene)
        var routeCount = 0
        var completionValues: [Bool] = []

        coordinator.handleApplicationShortcut(
            makeShortcut(),
            route: { _ in
                routeCount += 1
                return true
            },
            completionHandler: { completionValues.append($0) }
        )

        XCTAssertEqual(routeCount, 0)
        XCTAssertEqual(completionValues, [false])
        XCTAssertEqual(logger.errorCallsCount, 1)
    }

    func testHandleSceneConnection_givenNoActivation_thenReturnsNoActivation() {
        let coordinator = makeCoordinator(.uiScene)
        var routeCount = 0

        let result = handleSceneConnection(coordinator, routeCount: &routeCount)

        XCTAssertEqual(result, .noActivation)
        XCTAssertEqual(routeCount, 0)
    }

    func testHandleSceneConnection_givenOneURL_thenRoutesExactlyOnce() {
        let coordinator = makeCoordinator(.uiScene)
        var routeCount = 0

        let result = handleSceneConnection(coordinator, urls: [url], routeCount: &routeCount)

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(routeCount, 1)
    }

    func testHandleSceneConnection_givenOneUserActivity_thenRoutesExactlyOnce() {
        let coordinator = makeCoordinator(.uiScene)
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        var receivedActivity: NSUserActivity?

        let result = coordinator.handleSceneConnection(
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

    func testHandleSceneConnection_givenOneShortcut_thenRoutesExactlyOnce() {
        let coordinator = makeCoordinator(.uiScene)
        let shortcut = makeShortcut()
        var receivedShortcut: UIApplicationShortcutItem?

        let result = coordinator.handleSceneConnection(
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

    func testHandleSceneConnection_givenNotificationResponse_thenLeavesItApplicationOwned() {
        let coordinator = makeCoordinator(.uiScene)
        var routeCount = 0

        let result = handleSceneConnection(
            coordinator,
            hasNotificationResponse: true,
            routeCount: &routeCount
        )

        XCTAssertEqual(result, .notificationOwnedByApplication)
        XCTAssertEqual(routeCount, 0)
    }

    func testHandleSceneConnection_givenNotificationAndURL_thenRejectsAndLogs() {
        let coordinator = makeCoordinator(.uiScene)
        var routeCount = 0

        let result = handleSceneConnection(
            coordinator,
            urls: [url],
            hasNotificationResponse: true,
            routeCount: &routeCount
        )

        XCTAssertEqual(result, .rejectedAmbiguousInput)
        XCTAssertEqual(routeCount, 0)
        XCTAssertEqual(logger.errorCallsCount, 1)
    }

    func testHandleSceneConnection_givenMultipleURLs_thenRejectsWithoutRouting() {
        let coordinator = makeCoordinator(.uiScene)
        let secondURL = URL(string: "myapp://dashboard")!
        var routeCount = 0

        let result = handleSceneConnection(
            coordinator,
            urls: [url, secondURL],
            routeCount: &routeCount
        )

        XCTAssertEqual(result, .rejectedAmbiguousInput)
        XCTAssertEqual(routeCount, 0)
        XCTAssertEqual(logger.errorCallsCount, 1)
    }

    func testHandleSceneConnection_givenMultipleUserActivities_thenRejectsWithoutRouting() {
        let coordinator = makeCoordinator(.uiScene)
        let firstActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        let secondActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        var routeCount = 0

        let result = coordinator.handleSceneConnection(
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

    func testHandleSceneConnection_givenURLAndUserActivity_thenRejectsWithoutRouting() {
        let coordinator = makeCoordinator(.uiScene)
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        var routeCount = 0

        let result = coordinator.handleSceneConnection(
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

    func testHandleSceneConnection_givenRepeatedIdenticalURL_thenRoutesNewOccurrences() {
        let coordinator = makeCoordinator(.uiScene)
        var routeCount = 0

        for _ in 0 ..< 2 {
            XCTAssertEqual(
                handleSceneConnection(coordinator, urls: [url], routeCount: &routeCount),
                .handled
            )
        }

        XCTAssertEqual(routeCount, 2)
    }

    func testHandleSceneConnection_givenAppDelegateTopology_thenRejectsWithoutRouting() {
        let coordinator = makeCoordinator(.appDelegateOnly)
        var routeCount = 0

        let result = handleSceneConnection(coordinator, urls: [url], routeCount: &routeCount)

        XCTAssertEqual(result, .rejectedHostTopology)
        XCTAssertEqual(routeCount, 0)
    }

    func testHandleSceneOpenURLs_givenOneURL_thenRoutesExactlyOnce() {
        let coordinator = makeCoordinator(.uiScene)
        var receivedURLs: [URL] = []

        let result = coordinator.handleSceneOpenURLs([url]) { receivedURL in
            receivedURLs.append(receivedURL)
            return true
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(receivedURLs, [url])
    }

    func testHandleSceneOpenURLs_givenAppDelegateTopology_thenRejectsWithoutRouting() {
        let coordinator = makeCoordinator(.appDelegateOnly)
        var routeCount = 0

        let result = coordinator.handleSceneOpenURLs([url]) { _ in
            routeCount += 1
            return true
        }

        XCTAssertEqual(result, .rejectedHostTopology)
        XCTAssertEqual(routeCount, 0)
        XCTAssertEqual(logger.errorCallsCount, 1)
    }

    func testHandleSceneOpenURLs_givenNoURL_thenReturnsNoActivationWithoutRouting() {
        let coordinator = makeCoordinator(.uiScene)
        var routeCount = 0

        let result = coordinator.handleSceneOpenURLs([]) { _ in
            routeCount += 1
            return true
        }

        XCTAssertEqual(result, .noActivation)
        XCTAssertEqual(routeCount, 0)
    }

    func testHandleSceneOpenURLs_givenMultipleURLs_thenRoutesEveryURL() {
        let coordinator = makeCoordinator(.uiScene)
        let secondURL = URL(string: "myapp://dashboard")!
        var receivedURLs: [URL] = []

        let result = coordinator.handleSceneOpenURLs([url, secondURL]) { receivedURL in
            receivedURLs.append(receivedURL)
            return true
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(receivedURLs, [url, secondURL])
        XCTAssertEqual(logger.errorCallsCount, 0)
    }

    func testHandleSceneOpenURLs_givenMixedRouteResults_thenRoutesEveryURLAndReturnsHandled() {
        let coordinator = makeCoordinator(.uiScene)
        let secondURL = URL(string: "myapp://dashboard")!
        var receivedURLs: [URL] = []

        let result = coordinator.handleSceneOpenURLs([url, secondURL]) { receivedURL in
            receivedURLs.append(receivedURL)
            return receivedURL == secondURL
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(receivedURLs, [url, secondURL])
    }

    func testHandleSceneOpenURLs_givenEveryRouteDeclines_thenReturnsUnhandled() {
        let coordinator = makeCoordinator(.uiScene)
        let secondURL = URL(string: "myapp://dashboard")!
        var routeCount = 0

        let result = coordinator.handleSceneOpenURLs([url, secondURL]) { _ in
            routeCount += 1
            return false
        }

        XCTAssertEqual(result, .unhandled)
        XCTAssertEqual(routeCount, 2)
    }

    func testHandleSceneUserActivity_givenSceneTopology_thenRoutesExactlyOnce() {
        let coordinator = makeCoordinator(.uiScene)
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        var routeCount = 0

        let result = coordinator.handleSceneUserActivity(activity) { receivedActivity in
            routeCount += 1
            return receivedActivity === activity
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(routeCount, 1)
    }

    func testHandleSceneUserActivity_givenAppDelegateTopology_thenRejectsWithoutRouting() {
        let coordinator = makeCoordinator(.appDelegateOnly)
        var routeCount = 0

        let result = coordinator.handleSceneUserActivity(NSUserActivity(activityType: "test")) { _ in
            routeCount += 1
            return true
        }

        XCTAssertEqual(result, .rejectedHostTopology)
        XCTAssertEqual(routeCount, 0)
    }

    func testHandleSceneShortcut_givenRouteDeclines_thenCompletesFalseExactlyOnce() {
        let coordinator = makeCoordinator(.uiScene)
        var routeCount = 0
        var completionValues: [Bool] = []

        coordinator.handleSceneShortcut(
            makeShortcut(),
            route: { _ in routeCount += 1
                return false
            },
            completionHandler: { completionValues.append($0) }
        )

        XCTAssertEqual(routeCount, 1)
        XCTAssertEqual(completionValues, [false])
    }

    func testHandleSceneShortcut_givenAppDelegateTopology_thenRejectsAndCompletesFalseOnce() {
        let coordinator = makeCoordinator(.appDelegateOnly)
        let shortcut = UIApplicationShortcutItem(type: "test", localizedTitle: "Test")
        var routeCount = 0
        var completions: [Bool] = []

        let result = coordinator.handleSceneShortcut(
            shortcut,
            route: { _ in
                routeCount += 1
                return true
            },
            completionHandler: { completions.append($0) }
        )

        XCTAssertEqual(result, .rejectedHostTopology)
        XCTAssertEqual(routeCount, 0)
        XCTAssertEqual(completions, [false])
    }

    func testHandleSwiftUIOpenURL_givenSwiftUITopology_thenRoutesRepeatedOccurrences() {
        let coordinator = makeCoordinator(.swiftUILifecycle)
        var routeCount = 0

        for _ in 0 ..< 2 {
            XCTAssertEqual(
                coordinator.handleSwiftUIOpenURL(url) { _ in
                    routeCount += 1
                    return true
                },
                .handled
            )
        }

        XCTAssertEqual(routeCount, 2)
    }

    func testHandleSwiftUIOpenURL_givenSceneTopology_thenRejectsWithoutRouting() {
        let coordinator = makeCoordinator(.uiScene)
        var routeCount = 0

        let result = coordinator.handleSwiftUIOpenURL(url) { _ in
            routeCount += 1
            return true
        }

        XCTAssertEqual(result, .rejectedHostTopology)
        XCTAssertEqual(routeCount, 0)
        XCTAssertEqual(logger.errorCallsCount, 1)
    }

    private func makeCoordinator(
        _ topology: CioAppLifecycleHostTopology
    ) -> CioAppLifecycleCoordinator {
        CioAppLifecycleCoordinator(hostTopology: topology, logger: logger)
    }

    private func makeShortcut() -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(type: "settings", localizedTitle: "Settings")
    }

    private func handleSceneConnection(
        _ coordinator: CioAppLifecycleCoordinator,
        urls: [URL] = [],
        hasNotificationResponse: Bool = false,
        routeCount: inout Int
    ) -> CioAppLifecycleHandlingResult {
        coordinator.handleSceneConnection(
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
    ) -> CioAppLifecycleCoordinator.SceneConnectionActivation<URL> {
        CioAppLifecycleCoordinator.SceneConnectionActivation(
            urlActivations: urls,
            userActivities: userActivities,
            shortcutItem: shortcutItem,
            hasNotificationResponse: hasNotificationResponse
        )
    }
}
