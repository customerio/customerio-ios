# ADR 013 — Live Activities Asset Library

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Live Activities render inside a widget extension process. That process is
sandboxed separately from the main app and cannot load images from the network
or from the main app's bundle at render time. The only storage shared between
the main app and the widget extension is an AppGroup container.

To support image assets in Live Activity templates — including Customer.io
built-in templates and host-app custom activities — a facility is needed to:

1. Pre-load assets into the AppGroup from a declared source (Phase 1: app
   bundle; Phase 2: server-specified URLs).
2. Make those assets addressable by a stable key so the backend can reference
   them in push payloads.
3. Provide a widget-extension-safe resolution API so Live Activity views can
   look up assets by key at render time.

This work also motivated renaming the two existing Live Activity template
targets to better reflect their expanded scope.

---

## Decision

### Module renaming

The two template targets are renamed to reflect their actual roles:

| Old name | New name | Role |
|---|---|---|
| `CustomerIO_LiveActivities_TemplateAttributes` | `CustomerIO_LiveActivities_Attributes` | `ActivityAttributes` data contracts — shared between main app and widget extension |
| `CustomerIO_LiveActivities_Templates` | `CustomerIO_LiveActivitiesUI` | Widget views and asset resolution — widget extension only |

Source directories are renamed to match (`LiveActivities_TemplateAttributes` →
`LiveActivities_Attributes`, `LiveActivities_Templates` → `LiveActivitiesUI`).

### Storage — content-addressed, AppGroup-backed

Assets are stored in the AppGroup container at a well-known path:

```
{AppGroup}/cio/assets/manifest.json
{AppGroup}/cio/assets/{sha256}.{ext}
```

Files are named by the SHA-256 hash of their content plus the original file
extension (e.g. `a3f2c1….png`). This gives:

- **Automatic deduplication.** Two AssetKeys pointing to the same image store
  one file. A URL change with identical content produces no new file.
- **Trivial change detection.** If the stored hash matches the incoming hash,
  no copy or download is needed.
- **Cheap garbage collection.** After each manifest write, any file in the
  assets directory not referenced by the current manifest is deleted. No
  reference counting is required.

All writes use `Data.write(toFile:atomically:true)`, which performs an atomic
temp-file swap internally. The widget extension never reads a partially-written
file.

### Manifest format

```json
{
  "version": 1,
  "assets": {
    "hero_image": { "hash": "a3f2c1…", "ext": "png" },
    "logo":       { "hash": "7d9e4b…", "ext": "jpg" }
  }
}
```

The `version` field is included for forward compatibility. Readers that
encounter an unknown version should treat the manifest as empty rather than
failing.

The manifest path (`cio/assets/manifest.json`) is declared as a constant in
both `CustomerIO_LiveActivities` (writer) and `CustomerIO_LiveActivitiesUI`
(reader), with a comment in each noting that the two values must remain
identical. Importing `CustomerIO_Utilities` into the widget-extension-only
target solely for a single constant is not justified.

### AssetKey

Asset keys are plain `String` values. A dedicated `AssetKey` type was
considered but rejected: the type would need to be importable by both the main
app (`LiveActivityConfigBuilder`) and the widget extension
(`CustomerIO_LiveActivitiesUI`), and neither `CustomerIO_LiveActivities` (main
app, full SDK dependency chain) nor `CustomerIO_LiveActivities_Attributes`
(widget-safe, but scoped to `ActivityAttributes` types) is an appropriate home
for it. A separate micro-target solely for one string-wrapper type is not
justified. Plain `String` values agree at runtime by convention.

### Phase 1 — bundle assets

In Phase 1, asset sources are files already present in the main app bundle.
Registration on `LiveActivityConfigBuilder` accepts a non-optional `URL`:

```swift
// Primary — developer provides an already-resolved URL
builder.registerAsset("hero_image", at: url)

// Convenience — SDK resolves from the bundle and fails loudly if absent
builder.registerAsset("hero_image", bundleResource: "hero", withExtension: "png")
```

The convenience method calls `Bundle.main.url(forResource:withExtension:)` and
produces a `fatalError` with the missing resource name if the result is `nil`.
Silent failure (accepting `URL?` and skipping the asset) is explicitly rejected
— a misconfigured asset key is a developer error that must surface at launch,
not as a missing image at render time.

During `configure()`, the SDK hashes each declared bundle asset, compares
against the manifest, and copies changed or new files to the AppGroup. Assets
whose hash is unchanged are skipped. A GC sweep follows each write pass.

### Phase 2 — server-specified assets (future)

The server will supply an asset manifest containing `{ assetKey, url, hash }`
entries. The SDK will compare incoming hashes against the local manifest,
download only changed or new assets, verify the download against the declared
hash before writing, and run the same GC sweep. Token-based diffing (to avoid
re-fetching the full manifest) is deferred.

### `CIOAssetLibrary`

`CIOAssetLibrary` has two construction paths:

```swift
// Always succeeds. nil path produces a null instance — every asset
// request returns nil / renders an empty placeholder.
CIOAssetLibrary(path: URL?)

// Locates the AppGroup container and validates that a manifest exists
// (even an empty one). Throws if the container or manifest is absent.
CIOAssetLibrary(appGroup: String) throws
```

The null instance is the correct safe default: it compiles, runs, and produces
empty results without crashing. It is the right behavior both before
`configure()` is called and in contexts where no asset library is needed.

Resolution methods on `CIOAssetLibrary`:

```swift
func url(for key: String) -> URL?
func image(for key: String) -> some View   // renders empty placeholder on miss
```

### Widget-side access — `CIOLiveActivitiesUI`

The widget extension needs the `CIOAssetLibrary` instance before any view
renders. SwiftUI's `.environment()` modifier is a `View`-level API; there is
no hook above `Widget.body` in WidgetKit's architecture where environment
values can be injected for the whole bundle. The `Widget` protocol requires
`init()`, preventing constructor injection at the bundle level.

The consequence is a shared instance held on `CIOLiveActivitiesUI`:

```swift
public enum CIOLiveActivitiesUI {

    // Written once in WidgetBundle.init() before any Widget renders.
    // nonisolated(unsafe) is safe here: WidgetKit guarantees write-before-read
    // ordering via its lifecycle — no concurrent writes occur.
    nonisolated(unsafe) private static var _assetLibrary: CIOAssetLibrary
        = CIOAssetLibrary(path: nil)

    public static func configure(appGroup: String) {
        _assetLibrary = (try? CIOAssetLibrary(appGroup: appGroup))
            ?? CIOAssetLibrary(path: nil)
    }

    public static var assetLibrary: CIOAssetLibrary { _assetLibrary }
}
```

`configure()` is called once in `WidgetBundle.init()`:

```swift
@main
struct MyWidgetBundle: WidgetBundle {
    init() {
        CIOLiveActivitiesUI.configure(appGroup: "group.com.example")
    }
    …
}
```

`assetLibrary` is `public` so third-party Live Activity widgets that do not
use Customer.io built-in templates can access the shared instance directly.

Built-in templates inject the library into their view hierarchy automatically:

```swift
ActivityConfiguration(for: CIOScoreboardAttributes.self) { context in
    ScoreboardBannerView(state: context.state)
        .environment(\.cioAssetLibrary, CIOLiveActivitiesUI.assetLibrary)
}
```

Individual views read it via `@Environment(\.cioAssetLibrary)`. Third-party
widgets that need the library inject it the same way in their own
`ActivityConfiguration` closures.

The shared-instance pattern is a platform constraint, not a preference. A
`WidgetBundle`-level environment injection API does not exist in WidgetKit.
This is the minimal viable design given that constraint.

### AppGroup configuration

The AppGroup identifier is declared in two places:

- **Main app:** `LiveActivityConfigBuilder.appGroup(_:)` — used by the SDK
  when copying assets into the AppGroup container.
- **Widget extension:** `CIOLiveActivitiesUI.configure(appGroup:)` — used to
  construct the `CIOAssetLibrary` reader.

Both must receive the same identifier. The SDK does not attempt to validate
this at runtime.

---

## Consequences

### Enables

- Live Activity views can display images specified by the Customer.io backend
  without any network access at render time.
- Assets are deduplicated on disk by content hash, minimising AppGroup storage
  usage even when multiple keys reference the same image.
- Third-party custom Live Activity widgets can use `CIOLiveActivitiesUI.assetLibrary`
  without importing the full SDK.
- The Phase 2 server-driven manifest extends naturally from Phase 1: the
  storage format, manifest schema, and GC strategy are identical; only the
  source of the asset list changes.

### Constrains

- The AppGroup identifier must be declared in both the main app configuration
  and the widget extension configuration and kept in sync manually.
- The manifest path constant is duplicated between two targets and must be kept
  identical by convention, not by the compiler.
- `nonisolated(unsafe)` on `_assetLibrary` carries a write-before-read
  contract that the compiler cannot enforce. Violating it (calling
  `configure()` after the first widget renders) produces undefined behaviour.
- Phase 1 assets require an app update to change — they are compiled into the
  bundle. Dynamic asset updates require Phase 2.

---

## Rejected Alternatives

**Typed `AssetKey` struct** — rejected because no existing target is an
appropriate home for it that is importable by both the main app and the widget
extension without pulling in unrelated dependencies.

**`@EnvironmentObject` injection** — rejected because `EnvironmentObject`
requires `ObservableObject` and because there is no view above the Widget level
in WidgetKit to inject into.

**Widget constructor injection** — rejected because `WidgetBundle` constructs
widgets using `init()` by convention, and requiring every widget — including
third-party custom activities — to accept a constructor parameter adds friction
without a compensating benefit given the shared-instance approach.

**Accepting `URL?` in `registerAsset`** — rejected because silently skipping a
misconfigured asset key produces a missing image at render time with no
diagnostic. The project principle of explicit error states requires a loud
failure at launch.
