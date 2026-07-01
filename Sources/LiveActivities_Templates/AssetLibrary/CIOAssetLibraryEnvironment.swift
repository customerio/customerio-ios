import SwiftUI

// MARK: - Environment key

private struct CIOAssetLibraryKey: EnvironmentKey {
    static let defaultValue: CIOAssetLibrary = .init(path: nil)
}

public extension EnvironmentValues {
    /// The `CIOAssetLibrary` instance available to Live Activity views.
    ///
    /// Customer.io built-in templates inject `CIOLiveActivitiesTemplates.assetLibrary`
    /// into this key automatically. Custom Live Activity widgets can inject it
    /// themselves:
    /// ```swift
    /// ActivityConfiguration(for: MyAttributes.self) { context in
    ///     MyView()
    ///         .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
    /// }
    /// ```
    /// Views read it via `@Environment(\.cioAssetLibrary)`.
    var cioAssetLibrary: CIOAssetLibrary {
        get { self[CIOAssetLibraryKey.self] }
        set { self[CIOAssetLibraryKey.self] = newValue }
    }
}
