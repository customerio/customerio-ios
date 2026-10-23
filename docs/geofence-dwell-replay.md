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

The dwell coordinator accepts an internal wait function. Production uses a continuous-clock wait
where supported; replay supplies a cancellable virtual scheduler. Network answers, deadlines and retries
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

DWELL is deduplicated per continuous visit. ENTER and EXIT retain their separate cooldowns, so a
qualifying visit can emit DWELL even when its ENTER was suppressed by cooldown. A DWELL event does
not require a previously delivered ENTER.

`ReplayDwellSchedulerTests` also checks cancellation, deadline ordering and timers created during
boundary releases. `ReplayFixProviderTests` checks that re-reading a cached fix does not make it fresh.
Existing recorded corpus scenarios continue to run through `ScenarioReplayTests`.

## Capture compatibility and limits

The diagnostic catalogue tail includes raw `dwell=` seconds for circles and polygons. The companion
private converter preserves it as `dwellThresholdSeconds`; older captures omit the field and keep
the legacy disabled behavior. The converter has separate synthetic CLI regression tests.

The new dwell cases are synthetic. Existing corpus cases do not yet provide a recorded dwell drive.
Replay still uses bounded asynchronous settling between boundary releases. Assigning simultaneous
answers to multiple resolvers remains unmodeled. These tests do not
establish physical device scheduling, live backend ingestion, reboot or wall-clock-step
behavior. Existing coordinator tests cover several of those lifecycle rules separately.

## Suspension inputs

An authored scenario can freeze execution independently of backgrounding:

```json
{"k":"when","at":40,"ev":"app.suspend"}
{"k":"when","at":200,"ev":"app.resume"}
```

Wall time and continuous uptime advance while frozen. Timers and pending external answers stay held
until resume, when overdue work runs at the current time. A held location keeps its original
timestamp, so releasing it does not make it fresh. `app.background` alone does not freeze execution.

A scenario may end frozen; pending answers remain held. `process.start` and other SDK stimuli while
frozen are reported as unsupported. The same test process cannot discard an SDK continuation that
still awaits an answer. Resume before modeling a later process restart.

The polygon cases load real vertices through the API decoder and compare precise inside and outside
answers after resume. An outside answer inside the enclosing wake circle ends the visit without
DWELL. A precise inside answer can qualify one event at the fix's time, with the existing visit ID.
