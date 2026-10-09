# Automated dwell replay

`DwellReplayTests` drives the composed SDK through its real API decoder, condition-monitor callback,
visit persistence and event tracker. CoreLocation, HTTP, metric delivery and time use replay seams.
The synthetic tests run in the ordinary test job without the private corpus or device credentials.

```sh
xcodebuild -scheme Customer.io-Package \
  -destination 'platform=iOS Simulator,id=<simulator UUID>' \
  -only-testing:LocationGeofenceTests/DwellReplayTests \
  -only-testing:LocationGeofenceTests/ReplayDwellSchedulerTests \
  -only-testing:LocationGeofenceTests/ReplayFixProviderTests test
```

The result must include executed tests, not just a successful build or empty selection.
Use the installed Xcode developer directory when the global selection points at Command Line Tools.

## Virtual deadlines and evidence

The dwell coordinator accepts an internal wait function whose production default remains
`Task.sleep`. Replay supplies a cancellable virtual scheduler. Network answers, deadlines and retries
share one time-ordered loop, including deadlines created while another answer is being released.
Equal deadlines resume in registration order. A simulated process restart cancels the old timers
before the new SDK composition reads the persisted visits.

A deadline requests evidence; elapsed time alone does not prove the device is still inside.
OS answers pass through the shipping `MovementFixResolver` freshness filter, and cached fixes retain
their original age. Dwell consumes requested answers recorded at the current drive time; it cannot
borrow a later answer to close or qualify a visit early.
The suite checks fresh inside evidence, stale and uncertain fixes, proven outside membership,
duplicate callbacks, EXIT before the threshold, DWELL/EXIT visit identity and duration, re-entry,
process restart and a legacy catalogue with no threshold. A threshold different from the retry
delay guards against an immediate evidence request followed by a retry accidentally looking correct.

`ReplayDwellSchedulerTests` also checks cancellation, deadline ordering and timers created during
boundary releases. `ReplayFixProviderTests` checks that re-reading a cached fix does not make it fresh.
Existing recorded corpus scenarios continue to run through `ScenarioReplayTests`.

## Capture compatibility and limits

The diagnostic catalogue tail includes raw `dwell=` seconds for circles and polygons. The companion
private converter preserves it as `dwellThresholdSeconds`; older captures omit the field and keep
the legacy disabled behavior. The converter has separate synthetic CLI regression tests.

The new dwell cases are synthetic. Existing corpus cases do not yet provide a recorded dwell drive.
Replay still uses bounded asynchronous settling between boundary releases. Waiting for delayed
requested answers and assigning simultaneous answers to multiple resolvers remain unmodeled.
These tests do not
establish physical device scheduling, suspension, live backend ingestion, reboot or wall-clock-step
behavior. Existing coordinator tests cover several of those lifecycle rules separately.
