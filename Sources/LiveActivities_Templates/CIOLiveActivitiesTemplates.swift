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
    private nonisolated(unsafe) static var _assetLibrary: CIOAssetLibrary = .init(path: nil)

    // Set once in configure() alongside the asset library; see the note above for why
    // nonisolated(unsafe) is safe here.
    private nonisolated(unsafe) static var _branding: CIOActivityBranding?

    /// Configure the shared asset library and branding for the widget extension.
    ///
    /// Must be called exactly once, in `WidgetBundle.init()`, before any widget renders.
    /// If the AppGroup container or asset manifest cannot be found, the shared library
    /// silently degrades to a null instance — every asset request returns an empty
    /// placeholder rather than crashing.
    ///
    /// - Parameters:
    ///   - appGroup: The AppGroup container identifier declared in both the app target's
    ///     and widget extension target's entitlements.
    ///   - branding: App-level branding (logo, name, accent color) applied across every
    ///     Customer.io template. Shared for the whole app rather than set per activity
    ///     type. When `nil`, each template falls back to its built-in accent color and
    ///     omits the brand logo.
    public static func configure(appGroup: String, branding: CIOActivityBranding? = nil) {
        _assetLibrary = (try? CIOAssetLibrary(appGroup: appGroup)) ?? .init(path: nil)
        _branding = branding
    }

    /// The shared `CIOAssetLibrary` instance for this widget extension process.
    ///
    /// Returns a null instance (every lookup returns `nil` / empty placeholder)
    /// before `configure(appGroup:)` has been called.
    public static var assetLibrary: CIOAssetLibrary { _assetLibrary }

    /// The app-level branding supplied to `configure(appGroup:branding:)`, or `nil`
    /// if none was provided.
    public static var branding: CIOActivityBranding? { _branding }
}
