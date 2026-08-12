import Foundation
import XCTest

final class InMemoryLifecycleTraceSink: LifecycleTraceSink {
    private let lock = NSLock()
    private var storedLines: [String] = []

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedLines
    }

    func write(line: String) {
        lock.lock()
        storedLines.append(line)
        lock.unlock()
    }
}

// Recorder invariants intentionally share one fixture and deterministic clock.
// swiftlint:disable type_body_length
final class LifecycleTraceRecorderTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1754930800)
    private var sink: InMemoryLifecycleTraceSink!
    private var recorder: LifecycleTraceRecorder!

    override func setUp() {
        super.setUp()
        sink = InMemoryLifecycleTraceSink()
        recorder = makeRecorder(sink: sink)
        XCTAssertTrue(recorder.startScenario())
    }

    override func tearDown() {
        recorder = nil
        sink = nil
        super.tearDown()
    }

    func testRecord_whenScenarioDrains_thenEveryLineHasCanonicalRequiredShape() throws {
        XCTAssertTrue(recorder.record(
            callback: .sceneDidBecomeActive,
            owner: .sceneDelegate,
            kind: .osCallback,
            phase: .stateChange,
            observations: LifecycleTraceObservation(
                flags: [.hasScene: true],
                enums: [.sceneRole: "application", .sceneState: "foreground-active"],
                correlations: [.scene: .string("SECRET-SCENE-ID")]
            )
        ))
        let receipt = close(recorder)
        let records = try traceLines(in: sink).map(decode)

        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records.map { $0["sequence"] as? Int }, [1, 2, 3])
        XCTAssertEqual(records.first?["callback"] as? String, "trace.scenario-start")
        XCTAssertEqual(records.last?["callback"] as? String, "trace.scenario-end")
        let required: Set = [
            "schema", "manifest_id", "run_id", "stream_id", "sequence", "monotonic_ms",
            "captured_at", "process_id", "integration", "runtime", "provider", "scenario",
            "evidence_level", "owner", "kind", "callback", "phase", "main_thread",
            "payload_summary", "correlation", "completion", "recorder"
        ]
        for record in records {
            XCTAssertEqual(Set(record.keys), required)
            XCTAssertEqual(record["manifest_id"] as? String, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
            XCTAssertEqual(record["evidence_level"] as? String, "diagnostic")
            XCTAssertEqual(record["integration"] as? String, "native-ios")
            XCTAssertEqual(record["runtime"] as? String, "swift")
            XCTAssertFalse(String(describing: record).contains("SECRET-SCENE-ID"))
        }
        XCTAssertEqual(receipt?.lastAssignedSequence, 3)
        XCTAssertEqual(receipt?.lastEmittedSequence, 3)
        XCTAssertEqual(receipt?.emittedRecords, 3)
        let persistedReceipt = try decodeReceipt(in: sink)
        XCTAssertEqual(persistedReceipt["last_assigned_sequence"] as? Int, 3)
        XCTAssertEqual(persistedReceipt["emitted_records"] as? Int, 3)
    }

    func testStart_whenFirstRecord_thenRecorderStateIsPristine() throws {
        _ = close(recorder)
        let start = try decode(traceLines(in: sink)[0])
        let recorderState = try XCTUnwrap(start["recorder"] as? [String: Any])
        let aliases = try XCTUnwrap(recorderState["alias_counts"] as? [String: Any])

        XCTAssertEqual(start["sequence"] as? Int, 1)
        XCTAssertTrue(start["correlation"] is NSNull)
        XCTAssertEqual(recorderState["dropped_records_total"] as? Int, 0)
        XCTAssertEqual(recorderState["buffer_high_watermark"] as? Int, 1)
        XCTAssertEqual(aliases.values.compactMap { $0 as? Int }.reduce(0, +), 0)
    }

    func testRecord_whenProductionBufferOverflows_thenCaptureFailsClosedWithoutReceipt() throws {
        recorder.waitUntilDrainedForTesting()
        let boundedSink = InMemoryLifecycleTraceSink()
        let bounded = makeRecorder(sink: boundedSink, capacity: 256)
        XCTAssertTrue(bounded.startScenario())
        bounded.waitUntilDrainedForTesting()
        bounded.isDrainSchedulingPausedForTesting = true
        for _ in 0 ..< 256 {
            XCTAssertTrue(bounded.record(
                callback: .sceneDidBecomeActive,
                owner: .sceneDelegate,
                kind: .osCallback,
                phase: .stateChange,
                observations: LifecycleTraceObservation(
                    flags: [.hasScene: true],
                    enums: [.sceneRole: "application", .sceneState: "foreground-active"]
                )
            ))
        }
        XCTAssertFalse(bounded.record(
            callback: .sceneWillResignActive,
            owner: .sceneDelegate,
            kind: .osCallback,
            phase: .stateChange,
            observations: LifecycleTraceObservation(
                flags: [.hasScene: true],
                enums: [.sceneRole: "application", .sceneState: "foreground-inactive"]
            )
        ))
        bounded.isDrainSchedulingPausedForTesting = false
        bounded.waitUntilDrainedForTesting()
        let receipt = close(bounded)
        XCTAssertNil(receipt)
        XCTAssertEqual(try traceLines(in: boundedSink).map(decode).count, 1)
        XCTAssertFalse(boundedSink.lines.contains { $0.hasPrefix(LifecycleTraceRecorder.receiptPrefix) })
    }

    func testAliases_whenCapacityExceeded_thenCapAndOverflowAreCumulative() {
        let aliasSink = InMemoryLifecycleTraceSink()
        let aliasRecorder = makeRecorder(sink: aliasSink, capacity: 512)
        XCTAssertTrue(aliasRecorder.startScenario())
        for index in 0 ... 256 {
            XCTAssertTrue(aliasRecorder.record(
                callback: .hostRouteURL,
                owner: .host,
                kind: .hostRouting,
                phase: .intent,
                observations: LifecycleTraceObservation(correlations: [.delivery: .string("delivery-raw-\(index)")])
            ))
        }
        let receipt = close(aliasRecorder)

        XCTAssertEqual(receipt?.aliasCounts.delivery, 256)
        XCTAssertEqual(receipt?.aliasOverflow, true)
        XCTAssertEqual(receipt?.aliasOverflowNamespaces, [.delivery])
    }

    func testRecord_whenRawSecretsAreAliased_thenTheyNeverLeaveTheRecorder() throws {
        XCTAssertTrue(recorder.record(
            callback: .hostRouteURL,
            owner: .host,
            kind: .hostRouting,
            phase: .intent,
            observations: LifecycleTraceObservation(correlations: [
                .delivery: .string("SECRET-DELIVERY"),
                .request: .data(Data("SECRET-TOKEN".utf8)),
                .url: .string("customerio-test://secret?token=SECRET")
            ])
        ))
        _ = close(recorder)

        let joined = sink.lines.joined()
        XCTAssertFalse(joined.contains("SECRET"))
        XCTAssertFalse(joined.contains("customerio-test"))
        XCTAssertTrue(joined.contains("delivery-1"))
        XCTAssertTrue(joined.contains("request-1"))
        XCTAssertTrue(joined.contains("url-1"))
    }

    func testCompletionFixture_whenInvokedTwice_thenParentAndCountsAreCanonical() throws {
        let fixtureSink = InMemoryLifecycleTraceSink()
        let fixtureRecorder = makeRecorder(sink: fixtureSink, scenario: .unitFixture)
        XCTAssertTrue(fixtureRecorder.startScenario())
        let handle = try XCTUnwrap(fixtureRecorder.createCompletionFixture(
            closureIdentity: .string("fixture-owned-closure")
        ))
        XCTAssertTrue(fixtureRecorder.observeCompletionFixture(handle, result: .invoked))
        XCTAssertTrue(fixtureRecorder.observeCompletionFixture(handle, result: .invoked))
        _ = close(fixtureRecorder)
        let records = try traceLines(in: fixtureSink).map(decode)
        let creation = records[1]
        let outcomes = records[2 ... 3]

        XCTAssertEqual(creation["callback"] as? String, "fixture.completion-created")
        for (offset, record) in outcomes.enumerated() {
            let completion = try XCTUnwrap(record["completion"] as? [String: Any])
            XCTAssertEqual(completion["parent_sequence"] as? Int, 2)
            XCTAssertEqual(completion["call_index"] as? Int, offset + 1)
            XCTAssertEqual(completion["observed_call_count"] as? Int, offset + 1)
            XCTAssertEqual(completion["closure"] as? String, "closure-1")
        }
    }

    func testCompletionFixture_whenNegativeOutcomeBecomesDropAmbiguous_thenEndFailsClosed() throws {
        let fixtureSink = InMemoryLifecycleTraceSink()
        let fixtureRecorder = makeRecorder(sink: fixtureSink, scenario: .unitFixture, capacity: 2)
        XCTAssertTrue(fixtureRecorder.startScenario())
        fixtureRecorder.waitUntilDrainedForTesting()
        fixtureRecorder.isDrainSchedulingPausedForTesting = true
        let handle = try XCTUnwrap(fixtureRecorder.createCompletionFixture(closureIdentity: .string("fixture")))
        XCTAssertTrue(fixtureRecorder.observeCompletionFixture(handle, result: .notInvoked))
        XCTAssertFalse(fixtureRecorder.record(
            callback: .sceneDidBecomeActive,
            owner: .sceneDelegate,
            kind: .osCallback,
            phase: .stateChange
        ))

        let expectation = expectation(description: "fails closed")
        fixtureRecorder.endScenarioAndDrain { receipt in
            XCTAssertNil(receipt)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testRecord_whenCalledConcurrently_thenSequenceAndOutputStayOrdered() throws {
        let concurrentSink = InMemoryLifecycleTraceSink()
        let concurrentRecorder = makeRecorder(sink: concurrentSink, capacity: 512)
        XCTAssertTrue(concurrentRecorder.startScenario())
        DispatchQueue.concurrentPerform(iterations: 300) { _ in
            XCTAssertTrue(concurrentRecorder.record(
                callback: .sceneDidBecomeActive,
                owner: .sceneDelegate,
                kind: .osCallback,
                phase: .stateChange,
                observations: LifecycleTraceObservation(
                    flags: [.hasScene: true],
                    enums: [.sceneRole: "application", .sceneState: "foreground-active"]
                )
            ))
        }
        _ = close(concurrentRecorder)
        let sequences = try traceLines(in: concurrentSink).map { try XCTUnwrap(decode($0)["sequence"] as? Int) }

        XCTAssertEqual(sequences, Array(1 ... 302))
        XCTAssertEqual(Set(sequences).count, 302)
    }

    func testTerminalClose_whenEarlyTerminalIsInvalid_thenRealTerminalStillEndsAndPersistsReceipt() throws {
        let terminalSink = InMemoryLifecycleTraceSink()
        let terminalRecorder = makeRecorder(sink: terminalSink, scenario: .tokenRegistration)
        XCTAssertTrue(terminalRecorder.startScenario())

        var earlyCompletionCalled = false
        XCTAssertFalse(terminalRecorder.endScenario(after: .activeScene) { _ in
            earlyCompletionCalled = true
        })
        XCTAssertFalse(earlyCompletionCalled)
        XCTAssertTrue(terminalRecorder.record(
            callback: .applicationDidRegisterForRemoteNotifications,
            owner: .applicationDelegate,
            kind: .osCallback,
            phase: .entry,
            observations: LifecycleTraceObservation(
                flags: [.hasDeviceToken: true],
                counts: [.deviceTokenBytes: 32],
                correlations: [.request: .data(Data(repeating: 1, count: 32))]
            )
        ))
        XCTAssertTrue(terminalRecorder.record(
            callback: .customerIORegisterDeviceToken,
            owner: .customerIOSDK,
            kind: .sdkRouting,
            phase: .result,
            observations: LifecycleTraceObservation(
                flags: [.handled: true],
                enums: [.result: "success"]
            )
        ))

        let expectation = expectation(description: "accepted terminal receipt")
        XCTAssertTrue(terminalRecorder.endScenario(after: .tokenRegistration) { receipt in
            XCTAssertNotNil(receipt)
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 3)
        XCTAssertEqual(try traceLines(in: terminalSink).map(decode).last?["callback"] as? String, "trace.scenario-end")
        XCTAssertEqual(try decodeReceipt(in: terminalSink)["last_assigned_sequence"] as? Int, 4)
    }

    func testBackgroundForegroundClose_whenInitialActivationOccurs_thenArmsOnlyAfterBackground() throws {
        let lifecycleSink = InMemoryLifecycleTraceSink()
        let lifecycleRecorder = makeRecorder(sink: lifecycleSink, scenario: .appBackgroundForeground)
        XCTAssertTrue(lifecycleRecorder.startScenario())
        XCTAssertTrue(lifecycleRecorder.record(
            callback: .sceneDidBecomeActive,
            owner: .sceneDelegate,
            kind: .osCallback,
            phase: .stateChange
        ))
        XCTAssertFalse(lifecycleRecorder.endScenario(after: .activeScene) { _ in
            XCTFail("initial activation must not end a background/foreground scenario")
        })
        XCTAssertTrue(lifecycleRecorder.record(
            callback: .sceneDidEnterBackground,
            owner: .sceneDelegate,
            kind: .osCallback,
            phase: .stateChange
        ))
        XCTAssertTrue(lifecycleRecorder.record(
            callback: .sceneDidBecomeActive,
            owner: .sceneDelegate,
            kind: .osCallback,
            phase: .stateChange
        ))

        let expectation = expectation(description: "background foreground receipt")
        XCTAssertTrue(lifecycleRecorder.endScenario(after: .activeScene) { receipt in
            XCTAssertNotNil(receipt)
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 3)
        let callbacks = try traceLines(in: lifecycleSink).map(decode).compactMap { $0["callback"] as? String }
        XCTAssertEqual(callbacks.last, "trace.scenario-end")
        XCTAssertEqual(callbacks.filter { $0 == "scene.did-become-active" }.count, 2)
    }

    private func makeRecorder(
        sink: LifecycleTraceSink,
        scenario: LifecycleTraceScenario = .unscoped,
        capacity: Int = 256
    ) -> LifecycleTraceRecorder {
        let context = LifecycleTraceContext(
            manifestID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            runID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            streamID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            processID: 42,
            processInstanceID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
            integration: .nativeIOS,
            runtime: .swift,
            provider: scenario == .unitFixture ? .none : .apn,
            scenario: scenario,
            evidenceLevel: .diagnostic
        )
        let fixedDate = fixedDate
        return LifecycleTraceRecorder(
            context: context!,
            sink: sink,
            bufferCapacity: capacity,
            now: { fixedDate },
            monotonicMilliseconds: { 42000 }
        )
    }

    @discardableResult
    private func close(_ recorder: LifecycleTraceRecorder) -> LifecycleTraceStreamReceipt? {
        let expectation = expectation(description: "post-drain receipt")
        var result: LifecycleTraceStreamReceipt?
        recorder.endScenarioAndDrain { receipt in
            result = receipt
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
        return result
    }

    private func decode(_ line: String) throws -> [String: Any] {
        XCTAssertTrue(line.hasPrefix(LifecycleTraceRecorder.linePrefix))
        let json = line.dropFirst(LifecycleTraceRecorder.linePrefix.count)
        let data = try XCTUnwrap(String(json).data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func traceLines(in sink: InMemoryLifecycleTraceSink) -> [String] {
        sink.lines.filter { $0.hasPrefix(LifecycleTraceRecorder.linePrefix) }
    }

    private func decodeReceipt(in sink: InMemoryLifecycleTraceSink) throws -> [String: Any] {
        let line = try XCTUnwrap(sink.lines.last { $0.hasPrefix(LifecycleTraceRecorder.receiptPrefix) })
        let json = line.dropFirst(LifecycleTraceRecorder.receiptPrefix.count)
        let data = try XCTUnwrap(String(json).data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

// swiftlint:enable type_body_length
