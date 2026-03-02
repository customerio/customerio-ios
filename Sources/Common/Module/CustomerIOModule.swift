import Foundation

/// Marker protocol for module configuration types.
/// Each optional module (e.g. Location) defines its own config type; the builder only stores type-erased modules.
public protocol CustomerIOModuleConfig {}

/// A module is an optional Customer.io SDK feature that you can install in your app.
///
/// This protocol allows the base SDK to initialize all registered modules during `CustomerIO.initialize(withConfig:)`.
/// Add modules via `SDKConfigBuilder.addModule(_:)` before calling `build()`.
public protocol CustomerIOModule {
    /// Name of the module, used in logs (e.g. "Location").
    var moduleName: String { get }

    /// Performs one-time setup for this module. Called by the SDK during `CustomerIO.initialize(withConfig:)` after the core DataPipeline is initialized.
    func initialize()
}
