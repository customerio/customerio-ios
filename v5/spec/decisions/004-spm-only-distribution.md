# ADR 004 — Swift Package Manager as Sole Distribution Channel

**Status:** Accepted

---

## Context

The previous SDK supported CocoaPods as its primary distribution channel.
CocoaPods has been officially deprecated; the trunk repository will become
read-only in fall 2026.

## Decision

The SDK is distributed via **Swift Package Manager only**. No `.podspec` is
maintained or published.

## Consequences

### What this enables

- No dual-distribution maintenance burden (`.podspec` + `Package.swift`).
- Wrapper SDK compatibility:
  - **Flutter**: SPM plugin support has been available since Flutter 3.19 (early 2024).
    The Flutter wrapper declares its iOS native dependency via `Package.swift`.
  - **Expo**: Expo Modules API supports SPM for native modules. EAS Build handles resolution.

### What this constrains

- **React Native (bare)**: RN's iOS build system remains CocoaPods-centric at the
  framework level as of this writing. This is the broader community's problem to
  solve — CocoaPods deprecation affects every major iOS library, not just CIO.
  If the RN wrapper temporarily requires a pre-built binary bridge (via
  `swift-create-xcframework`), that is the wrapper team's concern and does not
  affect the SDK's distribution model.
- Apps that have not yet migrated from CocoaPods to SPM cannot adopt this SDK
  until they do.
