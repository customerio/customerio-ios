# Segment Storage Injection Spike — iOS Report

**Date:** 2026-05-20
**Repo:** `customerio-ios`
**Branch:** `spike/segment-storage-injection-2026-05-19` (off `origin/main` @ `63c32f54`, local only — never pushed)
**Sample app:** `Apps/APN-UIKit` (bundle id `io.customer.ios-sample.apn-spm.APN-UIKit`)
**Simulator:** iPhone 16 Pro Max, iOS 18.5 (UDID `CC49601D-8243-40F7-A557-9826A5410F2C`)
**Spike run UUID:** `DB7F9DF0-30F4-4D22-830C-8B257254539C`
**Snapshot taken:** ~20s after launch (before the 30s Segment flush would drain wrapped event files via upload)

## TL;DR

`Configuration.storageMode(.custom(WrappingDataStore))` does fully intercept the **event-queue** persistence path on iOS, but **does NOT intercept the UserDefaults state path**. `cdp-analytics-swift`'s `Storage.swift` writes `segment.userId`, `segment.anonymousId`, `segment.traits`, and `segment.settings` directly to `UserDefaults(suiteName: "com.segment.storage.<writeKey>")` regardless of what `StorageMode` is set. Those values land plaintext in `<container>/Library/Preferences/com.segment.storage.<writeKey>.plist`.

Verdict: **Phase 3 iOS is NOT feasible via `.custom(DataStore)` alone.** It requires a second injection layer (or a fork) to encrypt the UserDefaults suite, OR an explicit decision to accept plaintext `userId` / `traits` in UserDefaults backed by iOS Data Protection.

## What was implemented

1. New file `Sources/DataPipeline/Util/WrappingDataStore.swift` — a `DataStore` implementation that:
   - traces every protocol method via `os_log` (subsystem `io.customer.spike`, category `SegmentStorageTrace`)
   - on `append(data: RawEvent)`: serializes the event via `data.toString()`, prepends the 13-byte sentinel `WRAPPED::v1::`, then XOR's every byte after the sentinel with `0x55`, then writes the mutated bytes to one file per event under `Documents/spike-wrapping-storage/<writeKey>/NNNNNNNN-wrap.bin`
   - on `fetch`: re-reads each wrapped file, strips the sentinel, re-XORs back, assembles a fully-formed `{ "batch": [...], "sentAt": ..., "writeKey": ... }` JSON `Data` payload (same shape `MemoryStore` produces), returns it as `DataResult(data:removable:)`. `transactionType = .data` so `SegmentDestination.flushData` is used.
   - on `remove`: deletes wrapped files by URL
2. `Sources/DataPipeline/CustomerIO+Segment.swift` — added `result.storageMode(.custom(WrappingDataStore(...)))` to `toSegmentConfiguration()`.
3. `Apps/APN-UIKit/APN UIKit/AppDelegate.swift` — added `runSegmentStorageSpike()` called from `didFinishLaunchingWithOptions` after `initializeCioAndInAppListeners()`. The spike plants SPIKE_ needles via `identify` / `track` × 3 / `screen` / `alias`. `clearIdentify()` is intentionally omitted (it triggers `analytics.reset()` which wipes both the event queue and the UserDefaults plist, defeating the post-run grep).

Bundle id verified via pbxproj: `io.customer.ios-sample.apn-spm.APN-UIKit`. `preInitScenario` does not exist as a constant on this branch — nothing to leave at `.off`.

## Reconciliation table (every file in the post-run data container)

`SPIKE_? = grep -a 'SPIKE_' on the file bytes` (a → text-mode so binary bplists are checked too).

| File path (relative to data container) | Owned by | Contains `SPIKE_` plaintext? | Starts with `WRAPPED::v1::`? | Verdict |
|---|---|---|---|---|
| `.com.apple.mobile_container_manager.metadata.plist` | iOS | no | n/a | unrelated (OS) |
| `Documents/spike-wrapping-storage/45468ceeed7b7057c583/00000000-wrap.bin` | Segment events (via wrapper) | no | yes | wrapped |
| `Documents/spike-wrapping-storage/45468ceeed7b7057c583/00000001-wrap.bin` | Segment events (via wrapper) | no | yes | wrapped |
| `Documents/spike-wrapping-storage/45468ceeed7b7057c583/00000002-wrap.bin` | Segment events (via wrapper) | no | yes | wrapped |
| `Documents/spike-wrapping-storage/45468ceeed7b7057c583/00000003-wrap.bin` | Segment events (via wrapper) | no | yes | wrapped |
| `Documents/spike-wrapping-storage/45468ceeed7b7057c583/00000004-wrap.bin` | Segment events (via wrapper) | no | yes | wrapped |
| `Documents/spike-wrapping-storage/45468ceeed7b7057c583/00000005-wrap.bin` | Segment events (via wrapper) | no | yes | wrapped |
| `Documents/spike-wrapping-storage/45468ceeed7b7057c583/00000006-wrap.bin` | Segment events (via wrapper) | no | yes | wrapped |
| `Documents/spike-wrapping-storage/45468ceeed7b7057c583/00000007-wrap.bin` | Segment events (via wrapper) | no | yes | wrapped |
| `Documents/spike-wrapping-storage/45468ceeed7b7057c583/00000008-wrap.bin` | Segment events (via wrapper) | no | yes | wrapped |
| `Documents/spike-wrapping-storage/45468ceeed7b7057c583/00000009-wrap.bin` | Segment events (via wrapper) | no | yes | wrapped |
| `Documents/spike-wrapping-storage/45468ceeed7b7057c583/00000010-wrap.bin` | Segment events (via wrapper) | no | yes | wrapped |
| `Library/Caches/io.customer.ios-sample.apn-spm.APN-UIKit/Cache.db` (+ `-shm`, `-wal`) | URLSession cache | no | n/a | unrelated (OS HTTP cache) |
| `Library/HTTPStorages/io.customer.ios-sample.apn-spm.APN-UIKit/httpstorages.sqlite` (+ `-shm`, `-wal`) | URLSession cookie/storages | no | n/a | unrelated (OS HTTP store) |
| `Library/Preferences/com.segment.storage.45468ceeed7b7057c583.plist` | **Segment KVS (UserDefaults suite — NOT routed through DataStore)** | **YES — 3 SPIKE_ hits** | no | **BYPASSED** |
| `Library/Preferences/io.customer.ios-sample.apn-spm.APN-UIKit.plist` | CIO sample-app settings | no | n/a | unrelated (app config, no SDK profile data) |
| `Library/Preferences/io.customer.sdk.io.customer.ios-sample.apn-spm.APN-UIKit.shared.plist` | CIO shared GlobalDataStore (push token, in-app cache) | no | n/a | unrelated (no SPIKE_ leakage observed) |
| `Library/Saved Application State/.../data.data` | iOS UIScene state | no | n/a | unrelated (OS) |
| `Library/SplashBoard/Snapshots/...@3x.ktx` (x2) | iOS launch snapshot | no | n/a | unrelated (OS) |
| AppGroup `group.io.customer.ios-sample.apn-spm.APN-UIKit.cio` (container only contains `metadata.plist`) | iOS | no | n/a | unrelated (OS) |

Also note: the default Segment event-queue directory `Documents/segment/<writeKey>/` is created by `eventStorageDirectory()` but stays **empty** when `.custom` storage is set — proof that all `DataStore.append` traffic went through our wrapper.

## Needle leak report

Exactly one file in the post-run data container contains a `SPIKE_` needle in plaintext: the Segment UserDefaults suite plist.

```
File: <container>/Library/Preferences/com.segment.storage.45468ceeed7b7057c583.plist
Size: 762 bytes
Needles found (via `strings` + xxd):
  - SPIKE_TRAIT_email                                       (key in segment.traits nested bplist)
  - SPIKE_TRAIT_VALUE_DB7F9DF0-30F4-4D22-830C-8B257254539C  (value in segment.traits nested bplist)
  - SPIKE_ALIAS_DB7F9DF0-30F4-4D22-830C-8B257254539C        (string value of segment.userId — written by alias())
```

Hexdump preview (offsets where SPIKE_ appears):

```
00000200: 1153 5049 4b45 5f54 5241 4954 5f65 6d61  .SPIKE_TRAIT_ema
00000210: 696c 5f10 3653 5049 4b45 5f54 5241 4954  il_.6SPIKE_TRAIT
00000270: 3053 5049 4b45 5f41 4c49 4153 5f44 4237  0SPIKE_ALIAS_DB7
```

`plutil -p` output of the plist:

```
{
  "segment.anonymousId" => "749DB870-AAD5-4DD0-9BA6-84A4491FAF54"
  "segment.settings"    => <nested bplist: writeKey, hosts, sampleRate — no SPIKE_ here>
  "segment.traits"      => <nested bplist embedding SPIKE_TRAIT_email -> SPIKE_TRAIT_VALUE_...>
  "segment.userId"      => "SPIKE_ALIAS_DB7F9DF0-30F4-4D22-830C-8B257254539C"
}
```

The `SPIKE_USER_<uuid>` value originally written by `identify(userId:)` was overwritten in `segment.userId` by the subsequent `alias(newId:)`, which is consistent with Segment's documented `alias` semantics.

No `SPIKE_` hit elsewhere — every event file under `Documents/spike-wrapping-storage/<writeKey>/` is sentinel-prefixed and XOR-mutated.

## Trace log summary

Counts from `xcrun simctl spawn booted log stream --predicate 'subsystem == "io.customer.spike"'`:

| Operation | Count |
|---|---|
| `init`   | 1   |
| `append` | 11  |
| `fetch`  | 1   |
| `remove` | 11  |
| `reset`  | 0   |

The 11 `append` calls correspond to: 1 identify + 3 track + 1 screen + 1 alias + auto plugin events (`Device Created or Updated`, push token tracking, `Application Installed/Opened` lifecycle, etc). The single `fetch` happened ~30s after launch at the natural Segment flushInterval and the upload succeeded against `cdp.customer.io/v1`, which directly proves our `unwrap()` reconstructs valid JSON the server accepts. All 11 wrapped files were then `remove`d after the successful batch upload.

`fetch picked=11 plaintextBytes=13258 batchBytes=13352 firstPath=00000000-wrap.bin` — confirms unwrap+batch assembly produced a 13,352-byte JSON the upload pipeline used directly without ever seeing the wrapped bytes.

## UserDefaults-suite finding (the critical question)

**Did `com.segment.storage.<writeKey>.plist` contain the needles in plaintext? YES.**

Evidence:

1. The plist is at `<container>/Library/Preferences/com.segment.storage.45468ceeed7b7057c583.plist` (762 bytes, owner `mobile`).
2. `grep -a 'SPIKE_' <plist>` matches 3 distinct needles (above).
3. `plutil -p` decodes `segment.userId` as the literal string `"SPIKE_ALIAS_DB7F9DF0-30F4-4D22-830C-8B257254539C"`.
4. `segment.traits` decodes to a nested bplist whose UTF-8 byte stream contains `SPIKE_TRAIT_email` and `SPIKE_TRAIT_VALUE_DB7F9DF0-30F4-4D22-830C-8B257254539C` verbatim.
5. Our `WrappingDataStore` received **zero** writes for any of these — the trace log shows only 11 `append`s, all of which were `RawEvent`s (track/identify/screen/alias events, not the KVS state).

Source confirmation in `cdp-analytics-swift`:

- `Sources/Segment/Utilities/Storage/Storage.swift` line 24 constructs `UserDefaults(suiteName: "com.segment.storage.\(writeKey)")` independently of `storageMode`.
- The `switch key { case .events: dataStore.append(...) default: userDefaults.set(...) }` branch (line 60-89) means `userId`, `anonymousId`, `traits`, `settings` all flow to `userDefaults`, never through `DataStore`.
- `userInfoUpdate(state:)` (line 184) writes `userId`, `traits`, `anonymousId` reactively whenever Sovran state changes.

This is a hard, source-confirmed bypass of `.custom(DataStore)` — not a transient race.

## Verdict

**Phase 3 iOS requires a second injection layer** beyond `Configuration.storageMode(.custom(DataStore))`. Concrete options, in order of preference:

1. **Replace the `UserDefaults` suite with an encrypted KVS at runtime.** `cdp-analytics-swift`'s `Storage.swift` calls `UserDefaults(suiteName: "com.segment.storage.\(writeKey)")!` directly — no DI seam. To swap that backing store we would need to either (a) fork (or vendor) the library to inject a key-value protocol, or (b) take the Apple-private-but-historically-allowed route of registering a `UserDefaults` subclass via `URLProtocol`-style runtime swizzling on `UserDefaults`, which is fragile and likely AppStore-risky.

2. **Accept plaintext `userId` / `anonymousId` / `traits` in UserDefaults, encrypt only the event queue via `.custom(DataStore)`** (the spike proves this half works). Pair with iOS Data Protection class (`NSFileProtectionComplete` / `CompleteUnlessOpen`) on the Preferences plist to gate at-rest exposure to device-unlocked state. This is the lower-risk path; the trade-off is that `userId` and `traits` are encrypted only by the OS file-protection key, not our `CryptoProvider`.

3. **Fork `cdp-analytics-swift`** to add a `keyValueStore: any KeyValueStore` configuration field and route `Storage.userDefaults` access through it. Maintenance cost is real but bounded (the library doesn't change `Storage.swift` often).

Recommend pursuing option 2 (accept + Data Protection) for Phase 3 v1, with option 3 reserved as a follow-up if a stronger guarantee is required.

Half of Phase 3 (event queue) is unblocked: `.custom(DataStore)` cleanly intercepts every byte of the event-batch persistence path, and a `CryptoProvider` can plug into the same seam this spike used. The other half (KVS / profile state) needs a separate design.

## Branch state

- Branch name: `spike/segment-storage-injection-2026-05-19`
- Created from: `origin/main` @ `63c32f54a refactor: Added Synchronized primitive and tests for it (#1049)`
- Push status: **not pushed** (local only — per spike rules)
- Files changed on the branch (vs `origin/main`):
  - `Sources/DataPipeline/Util/WrappingDataStore.swift` — new
  - `Sources/DataPipeline/CustomerIO+Segment.swift` — `.storageMode(.custom(WrappingDataStore(...)))` added to `toSegmentConfiguration()`
  - `Apps/APN-UIKit/APN UIKit/AppDelegate.swift` — `runSegmentStorageSpike()` added + call from `didFinishLaunchingWithOptions`
- `main` branch is untouched; the only commits on this branch live on the spike branch.
- No `preInitScenario` toggle exists on this codebase to disturb.

## Raw artifacts

- Trace log: `/tmp/spike-oslog.txt`
- Console capture (from `simctl launch --console-pty`): `/tmp/spike-console.txt`
- Filesystem snapshot of post-run data container: `/tmp/spike-snapshot/` (full `cp -R` of the container at the 20s mark)
- File list: `/tmp/spike-files-data.txt`
