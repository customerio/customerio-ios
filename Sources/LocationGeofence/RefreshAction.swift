import Foundation

/// The kind of refresh a signal calls for, decided independently of what triggered it.
///
/// - `remote` — fetch a fresh set from the API.
/// - `local`  — re-rank / re-register the cached set on-device, no network.
/// - `skip`   — cache is current; do nothing.
enum RefreshAction: Equatable {
    case remote
    case local
    case skip
}
