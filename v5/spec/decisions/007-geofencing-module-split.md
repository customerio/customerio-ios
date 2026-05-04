# ADR 007 — Geofencing as a Separate Module from Location

**Status:** Accepted

---

## Context

Geofencing was initially configured as a sub-capability of `LocationConfig` (via
a nested `GeofenceConfig`), with `GeofenceCoordinator` owned and started by
`LocationModule`. The original rationale was that geofencing requires a device
location to select which regions to hand to `CLLocationManager`.

Closer analysis revealed this coupling is unnecessary:
- `GeofenceCoordinator` already owns its own `CLLocationManager` instance used
  purely for region monitoring.
- Adding `startMonitoringSignificantLocationChanges()` to that same manager makes
  the coordinator fully self-contained for candidate selection — coarse ~500 m
  fixes are sufficient to decide which 20 geofences to activate.
- `LocationMode` governs what CIO *reports to the server*; candidate selection is
  purely internal and never reported.
- When both modules are active, CoreLocation deduplicates the radio work at the
  OS level — no power penalty.

## Decision

Split Geofencing into an independent `CustomerIO_Geofencing` SPM target and
product. An app can register `Geofencing` without registering `Location`.

Key changes:
- `QuadKey.swift` moved to `CustomerIO_Utilities` (both modules need it)
- All geofence types moved to `Sources/Geofencing/`
- `SdkConfigBuilder.geofencing { }` is a top-level builder extension, not nested
  under `.location { }`
- `cio.geofencing` accessor added via `CustomerIO+Geofencing.swift`
- `GeofencingModule` conforms to `CIOModule` + `MigrationProviding` independently

## Consequences

### What this enables

- An app that wants geofence enter/exit events but no CIO location tracking can
  use `Geofencing` alone, without being forced to configure a `LocationConfig`.
- The two modules compose independently: both, either, or neither can be registered.
- Each module's `CLLocationManager` usage is fully encapsulated; no ownership
  handoff between modules.

### What this constrains

- Apps upgrading from a version where geofencing was nested under location must
  update their `SdkConfigBuilder` calls — this is a breaking configuration change.
- `QuadKey` is now in `CustomerIO_Utilities`, making it theoretically accessible
  to all targets. It remains an implementation detail; no public API surface
  exposes it.
