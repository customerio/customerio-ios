# ADR 002 — SqlCipher for All On-Device Storage

**Status:** Accepted

---

## Context

The previous SDK stored its event queue and profile data in plain text
(`UserDefaults` and `EventStorageManager` flat files). Events routinely carry
PII — user identifiers, traits, and behavioral data. Per ADR 001, encrypting
the queue requires owning the storage layer entirely.

## Decision

All data written to disk uses **SqlCipherKit**. `UserDefaults` and flat-file JSON
storage are removed entirely from the new SDK.

- The passphrase is supplied by a `DatabaseKeyProvider` protocol, configured at
  SDK init time via `SdkConfigBuilder.databaseKeyProvider(_:)`.
- Two implementations are provided out of the box:
  - `ApiKeyDatabaseKeyProvider` (default) — uses the CDP API key verbatim.
  - `KeychainDatabaseKeyProvider` — generates a 256-bit random key on first
    launch, stored in the Keychain with `kSecAttrAccessibleAfterFirstUnlock`.
- The database filename and Keychain account name are both scoped to the CDP API
  key. Rotating the API key automatically produces a new database file and a new
  Keychain entry; the old database is orphaned without an explicit cleanup step.

## Consequences

### What this enables

- All PII stored by the SDK is encrypted at rest, regardless of device
  encryption state.
- `KeychainDatabaseKeyProvider` provides per-install, hardware-bound key
  isolation, inaccessible even to someone with the app binary.
- A single `StorageManager` struct serves as the stateless gateway for all
  modules; module-specific query methods live in extensions inside their owning
  module target.

### What this constrains

- SqlCipherKit is a required dependency for the entire SDK. Apps that do not
  need encryption cannot opt out.
- Database migrations must be managed explicitly via `MigrationRunner`. Each
  module that adds tables must register a `Migration` conformance.
- The `StorageManager.db` property is `package` access — visible within the
  Swift package but not to external consumers.
