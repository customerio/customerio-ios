import Foundation

/// Entry point for the `CIOLiveActivities_Templates` module.
///
/// Call `configure(appGroup:)` once in `WidgetBundle.init()` before any widget
/// renders. All built-in Customer.io templates inject the shared `assetLibrary`
/// into their view environments automatically. Third-party Live Activity widgets
/// can access it via `CIOLiveActivitiesTemplates.assetLibrary`.
///
/// ```swift
/// @main
/// struct MyWidgetBundle: WidgetBundle {
///     init() {
///         CIOLiveActivitiesTemplates.configure(appGroup: "group.com.example.app")
///     }
///     var body: some Widget {
///         CIODeliveryTrackingLiveActivity()
///     }
/// }
/// ```
public enum CIOLiveActivitiesTemplates {

    // Constructed once in configure() and then read-only for the process lifetime.
    // nonisolated(unsafe) is safe here: WidgetKit guarantees that configure() is
    // called in WidgetBundle.init() before any Widget.body is evaluated, so the
    // single write always happens before any reads. No concurrent writes occur.
    nonisolated(unsafe) private static var _assetLibrary: CIOAssetLibrary = .init(path: nil)

    /// Configure the shared asset library for the widget extension.
    ///
    /// Must be called exactly once, in `WidgetBundle.init()`, before any widget renders.
    /// If the AppGroup container or asset manifest cannot be found, the shared library
    /// silently degrades to a null instance — every asset request returns an empty
    /// placeholder rather than crashing.
    ///
    /// - Parameter appGroup: The AppGroup container identifier declared in both
    ///   the app target's and widget extension target's entitlements.
    public static func configure(appGroup: String) {
        _assetLibrary = (try? CIOAssetLibrary(appGroup: appGroup)) ?? .init(path: nil)
    }

    /// The shared `CIOAssetLibrary` instance for this widget extension process.
    ///
    /// Returns a null instance (every lookup returns `nil` / empty placeholder)
    /// before `configure(appGroup:)` has been called.
    public static var assetLibrary: CIOAssetLibrary { _assetLibrary }
}
