# Dwell acquisition experiments

These experiments are off by default. Acquisition keeps an opportunity to request fresh polygon
proof; it does not change accuracy, freshness, elapsed-time or visit-identity checks.

## Pending polygon collection

Set `CIOGeofenceExperimentalPendingDwellBackgroundCollection` to Boolean `true` in the host app's
Info.plist. The host must also declare the `location` background mode and already have Always and
Precise Location access. The SDK does not request new permission for this experiment. The shared
background bootstrap reads the same flag, including launches before SDK initialization.
Collection requires iOS 16 or later for the supported continuous-clock wait. On iOS 13–15, this
experiment remains off even when the flag is set; ordinary geofencing and dwell behavior continue.

One low-power location session serves pending polygon visits with thresholds up to two hours.
It requests three-kilometer accuracy and a 3,000 m distance filter, with automatic pausing disabled.
The session's delegate discards each callback's payload directly: it reads no location or error, so it
passes no fix to the polygon resolver and restarts no evidence retry. Every callback, whether a
location update, an error or an authorization change, only reconciles the session's lifetime. The
authorization callback also catches a permission change, including the one Core Location delivers
just after the session creates its manager. Discarding the payload does not isolate Core Location's
own state: whether a location this session caused can also reach another location manager's cached
location has not been established. Any location the resolver does read still goes through its
existing freshness and accuracy checks.

Each visit has a fixed cap from when it was originally recorded: threshold plus a fixed 220-second
grace, which the retry spacing does not lengthen. The cap is 3,820 seconds for a one-hour visit, measured on
continuous uptime and scheduled with a continuous-clock wait. An expiry job that starts late checks
the absolute cap before waiting. iOS can still delay execution; the cap does not guarantee a process
wake or an exact stop time. Repeated ENTERs and foreground re-arming do not extend the cap. EXIT, reservation, catalog changes, lost access and
identity changes release the affected lease, as does a visit spending its dwell-proof budget. Another
pending visit can keep the shared session alive.

The normal resolver still decides polygon membership. Merely reaching the dwell threshold,
receiving a region callback or keeping a session running does not produce DWELL. The polygon
resolver asks Core Location for `kCLLocationAccuracyNearestTenMeters`, a desired accuracy rather than
a guarantee; each verdict uses the accuracy the fix reports. A fresh fix is bounded by age, and a
pass that requires one accepts only a fix delivered after its request and newer than the last fix the
resolver received. That does not guarantee a new measurement: Core Location may answer with a recent
location it already held.

The short retry is normal SDK behavior for circles and polygons, regardless of these experiment
flags. If an inside measurement falls just before the dwell threshold, the SDK can spend one of its
four dwell-proof requests on a shorter wait based on that timing shortfall, never less than 30 seconds
nor more than 60. The first check still runs at the threshold, and a circle's short retry requests a
newer measurement. Later failures keep the normal 120-second spacing. This does not extend the
collection cap or qualify a stay without proof.

## Dwell-proof budget and small polygons

This applies with or without the experiments. The SDK issues at most four location requests per
visit to prove its dwell: one at the threshold and up to three retries, at least 120 seconds apart
except for the short retry. The count is stored with the visit, so returning to the foreground,
resuming or relaunching does not replenish it. A cached answer, or one shared with a request already
in flight, is not counted: on iOS, a request shared with a membership pass or with another visit's
dwell check is not charged to the visit that joins it. Each visit also runs at most eight dwell checks,
counted whether a request answered them or not. Once either limit is reached, the SDK schedules no more
dwell checks for that visit and logs `dwell proof budget exhausted` with the fence ID. A dwell already
proven and awaiting delivery needs no location, so neither limit holds back its delivery. Location requests the SDK makes for
ENTER and EXIT are not counted or limited, and a qualifying fix one of them returns can still prove
the dwell.

A fix proves presence only when its whole accuracy circle lies inside the polygon. A polygon whose
largest interior clearance is under about 10 m may therefore miss DWELL, especially indoors, where
phone fixes are rarely that tight. A larger circle fence is one alternative, but it monitors a
different footprint, so treat that as a product choice rather than an equivalent.

Physical-device screen-off testing is still required to establish whether the OS keeps this session
alive, lets it start from a short background wake, and lets pending deadlines run near their due
time. Session callbacks can arrive in the foreground or just after the session starts, so their
records do not show that iOS woke the process. Measure lateness by comparing each `deadlineReached`
record's `atUptime` with its `deadlineUptime`.

## Persistent diagnostics

Set `CIOGeofenceExperimentalDwellDiagnosticJournal` to Boolean `true` independently of collection.
The journal lives in Application Support at `io.customer.dwell-diagnostics/journal-v1.json` and
keeps at most 64 records by default. Records contain uptime, fence IDs, request accuracy labels,
returned accuracy and fix age, without coordinates or user/device IDs. Fence IDs and timing remain
location-derived history. Identity changes, reset and opt-out clear it. A protected sidecar stores
only the context record's opaque identity version and lineage, allowing a same-identity relaunch to
retain history while a different identity clears it before any append.

A `requestedAccuracy` label names the accuracy a request asked for, which is not a promise;
`returnedAccuracy` is what the fix reported. A `belowThreshold` rejection includes the optional
`thresholdShortfall`, in seconds, when the elapsed time could be measured. Older journal records
remain readable without that field. Each pending-dwell session callback is recorded by its
kind, as `sessionLocationCallback`, `sessionErrorCallback` or `sessionAuthorizationCallback`, under
the run that started the session, so a reset or identity change leaves that run's late callbacks
unrecorded. Journals from earlier builds may hold `wakeSession`, which covered all three kinds; it is
still read and no longer written. `wakeRegion` and `wakeVisit` record that a region or visit callback
ran, which can happen while the app is already running, and `wakeForeground` records a return to the
foreground. None of these records shows on its own that iOS woke or resumed the process.

Polygon passes that a pending dwell requests for its evidence log `why=dwell_evidence`, with the prose
"dwell evidence". Earlier builds logged them as `foreground`, whatever caused them. The reason names
the request's purpose; its cause appears separately, as a callback, a foreground change or, in the
journal, a `deadlineReached` record.

The file is excluded from backups and uses protection until first unlock after boot. It stays local;
the journal does not send data to the backend.

## Automated checks

[The replay harness](geofence-dwell-replay.md) models explicit suspension and resume with real polygon
fixtures. `GeofenceDwellCoordinatorTests` also drives the collection cap, overlapping visits, catalog
changes and a reserved DWELL whose outbox write fails. `PendingDwellLocationSessionTests` checks
host capability and permission eligibility using a fake location manager. It also checks that each
Core Location callback is recorded by its kind and still reconciles the owner, that a run's late
callbacks stay out of the journal after a reset or identity change, and that a journal holding the
earlier `wakeSession` still reads.

These checks establish SDK decisions and lifecycle rules. They do not establish physical background
execution or live backend delivery.
