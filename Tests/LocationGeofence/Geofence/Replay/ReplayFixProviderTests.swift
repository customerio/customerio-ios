@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

@Suite("Replay fix provider")
@MainActor
struct ReplayFixProviderTests {
    private let epoch = Date(timeIntervalSince1970: 1000000000)

    private func answer(at: TimeInterval, accuracy: Double, age: TimeInterval = 0.5) -> ReplayFixProvider.CachedRead {
        ReplayFixProvider.CachedRead(
            at: at, location: LocationData(latitude: 25.1, longitude: 55.2), accuracy: accuracy, age: age
        )
    }

    @Test
    func requestedAnswer_givenAnAnswerInsideTheTimeout_expectItWithItsAccuracyAndAge() {
        let provider = ReplayFixProvider(epoch: epoch)
        provider.loadRequestedAnswers([answer(at: 13.7, accuracy: 29.6, age: 0.7)])
        provider.now = 3.7

        let fix = provider.requestedAnswer(within: 10)

        #expect(fix?.horizontalAccuracy == 29.6)
        #expect(fix?.timestamp == epoch.addingTimeInterval(3.7 - 0.7))
    }

    @Test
    func requestedAnswer_givenTheAnswerIsConsumed_expectTheNextRequestGetsTheNextOne() {
        let provider = ReplayFixProvider(epoch: epoch)
        provider.loadRequestedAnswers([answer(at: 5, accuracy: 20), answer(at: 6, accuracy: 10)])
        provider.now = 4

        #expect(provider.requestedAnswer(within: 10)?.horizontalAccuracy == 20)
        #expect(provider.requestedAnswer(within: 10)?.horizontalAccuracy == 10)
        #expect(provider.requestedAnswer(within: 10) == nil)
    }

    @Test
    func requestedAnswer_givenOnlyAnAnswerPastTheTimeout_expectNone() {
        let provider = ReplayFixProvider(epoch: epoch)
        provider.loadRequestedAnswers([answer(at: 30, accuracy: 20)])
        provider.now = 4

        #expect(provider.requestedAnswer(within: 10) == nil)
    }

    /// An answer recorded before this request belonged to a request the replay did not make; it
    /// must not be handed to a later one.
    @Test
    func requestedAnswer_givenAnAnswerRecordedBeforeTheRequest_expectItSkipped() {
        let provider = ReplayFixProvider(epoch: epoch)
        provider.loadRequestedAnswers([answer(at: 2, accuracy: 50), answer(at: 12, accuracy: 15)])
        provider.now = 10

        #expect(provider.requestedAnswer(within: 10)?.horizontalAccuracy == 15)
    }

    @Test
    func requestedAnswer_givenACaptureWithNoAnswers_expectNoneSoTheCallerFallsBack() {
        let provider = ReplayFixProvider(epoch: epoch)
        provider.now = 4

        #expect(provider.requestedAnswer(within: 10) == nil)
    }
}
