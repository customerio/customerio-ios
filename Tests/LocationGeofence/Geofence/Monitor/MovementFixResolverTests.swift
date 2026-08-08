@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import SharedTests
import Testing

@Suite("MovementFixResolver")
@MainActor
struct MovementFixResolverTests {
    private func makeResolver(
        maxAge: TimeInterval = 30,
        requestTimeout: TimeInterval = 30,
        onRequest: @escaping () -> Void = {}
    ) -> MovementFixResolver {
        let resolver = MovementFixResolver(logger: LoggerMock(), maxAge: maxAge, requestTimeout: requestTimeout)
        resolver.requestFreshFix = onRequest
        return resolver
    }

    private func makeFix(latitude: Double = 31.0, longitude: Double = 74.0, ageSeconds: TimeInterval) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: Date(timeIntervalSinceNow: -ageSeconds)
        )
    }

    @Test
    func resolve_givenFreshCachedFix_expectImmediateCompletionWithoutRequest() {
        var requestCount = 0
        let resolver = makeResolver(onRequest: { requestCount += 1 })
        var received: [LocationData?] = []

        resolver.resolve(cached: makeFix(latitude: 31.5, ageSeconds: 5)) { received.append($0) }

        #expect(received.map(\.?.latitude) == [31.5])
        #expect(requestCount == 0)
    }

    @Test
    func resolve_givenStaleCachedFix_expectRequestThenCompletionWithFreshFix() {
        var requestCount = 0
        let resolver = makeResolver(onRequest: { requestCount += 1 })
        var received: [LocationData?] = []

        resolver.resolve(cached: makeFix(latitude: 31.1, ageSeconds: 120)) { received.append($0) }
        #expect(received.isEmpty)
        #expect(requestCount == 1)

        resolver.handleResolvedFix(makeFix(latitude: 31.9, ageSeconds: 0))
        #expect(received.map(\.?.latitude) == [31.9])
    }

    @Test
    func resolve_givenNoCachedFix_expectRequestAndNilOnFailure() {
        var requestCount = 0
        let resolver = makeResolver(onRequest: { requestCount += 1 })
        var received: [LocationData?] = []

        resolver.resolve(cached: nil) { received.append($0) }
        #expect(requestCount == 1)

        resolver.handleRequestFailure()
        #expect(received.count == 1)
        #expect(received[0] == nil)
    }

    @Test
    func resolve_givenStaleCachedFixAndFailure_expectFallbackToStaleFix() {
        let resolver = makeResolver()
        var received: [LocationData?] = []

        resolver.resolve(cached: makeFix(latitude: 31.2, ageSeconds: 120)) { received.append($0) }
        resolver.handleRequestFailure()

        #expect(received.map(\.?.latitude) == [31.2])
    }

    @Test
    func resolve_givenConcurrentResolutions_expectSingleRequestAndBothComplete() {
        var requestCount = 0
        let resolver = makeResolver(onRequest: { requestCount += 1 })
        var first: [LocationData?] = []
        var second: [LocationData?] = []

        resolver.resolve(cached: makeFix(ageSeconds: 120)) { first.append($0) }
        resolver.resolve(cached: makeFix(ageSeconds: 90)) { second.append($0) }
        #expect(requestCount == 1)

        resolver.handleResolvedFix(makeFix(latitude: 32.0, ageSeconds: 0))
        #expect(first.map(\.?.latitude) == [32.0])
        #expect(second.map(\.?.latitude) == [32.0])
    }

    @Test
    func resolve_givenTimeout_expectFallbackCompletionExactlyOnce() async {
        let resolver = makeResolver(requestTimeout: 0.05)
        var received: [LocationData?] = []

        resolver.resolve(cached: makeFix(latitude: 31.3, ageSeconds: 120)) { received.append($0) }

        for _ in 0 ..< 200 {
            if !received.isEmpty { break }
            try? await Task.sleep(nanoseconds: 10000000)
        }
        #expect(received.map(\.?.latitude) == [31.3])

        // A fix landing after the timeout must not re-complete, only refresh `latestFix`.
        resolver.handleResolvedFix(makeFix(latitude: 32.5, ageSeconds: 0))
        #expect(received.count == 1)
        #expect(resolver.latestFix?.coordinate.latitude == 32.5)
    }

    @Test
    func resolve_givenNewerCachedFixWhileRequestInFlight_expectFallbackToNewestCached() {
        let resolver = makeResolver()
        var first: [LocationData?] = []
        var second: [LocationData?] = []

        resolver.resolve(cached: makeFix(latitude: 31.6, ageSeconds: 120)) { first.append($0) }
        resolver.resolve(cached: makeFix(latitude: 31.7, ageSeconds: 90)) { second.append($0) }
        resolver.handleRequestFailure()

        #expect(first.map(\.?.latitude) == [31.7])
        #expect(second.map(\.?.latitude) == [31.7])
    }

    @Test
    func didUpdateLocations_givenInvalidCoordinate_expectIgnoredUntilValidFix() {
        let resolver = makeResolver()
        var received: [LocationData?] = []

        resolver.resolve(cached: nil) { received.append($0) }
        resolver.locationManager(CLLocationManager(), didUpdateLocations: [
            makeFix(latitude: 200.0, longitude: 200.0, ageSeconds: 0)
        ])
        #expect(received.isEmpty)

        resolver.locationManager(CLLocationManager(), didUpdateLocations: [
            makeFix(latitude: 31.8, ageSeconds: 0)
        ])
        #expect(received.map(\.?.latitude) == [31.8])
    }

    @Test
    func latestFix_givenOlderDeliveredFix_expectNewestRetained() {
        let resolver = makeResolver()

        resolver.handleResolvedFix(makeFix(latitude: 31.4, ageSeconds: 10))
        resolver.handleResolvedFix(makeFix(latitude: 31.5, ageSeconds: 60))

        #expect(resolver.latestFix?.coordinate.latitude == 31.4)
    }

    @Test
    func resolve_givenSecondResolveAfterCompletion_expectNewRequestCycle() {
        var requestCount = 0
        let resolver = makeResolver(onRequest: { requestCount += 1 })
        var received: [LocationData?] = []

        resolver.resolve(cached: makeFix(ageSeconds: 120)) { received.append($0) }
        resolver.handleResolvedFix(makeFix(latitude: 32.1, ageSeconds: 0))

        resolver.resolve(cached: makeFix(ageSeconds: 120)) { received.append($0) }
        #expect(requestCount == 2)

        resolver.handleResolvedFix(makeFix(latitude: 32.2, ageSeconds: 0))
        #expect(received.map(\.?.latitude) == [32.1, 32.2])
    }
}
