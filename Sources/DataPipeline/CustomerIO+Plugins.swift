import CioAnalytics
import CioInternalCommon
import Foundation

public extension CustomerIO {
    /**
     Applies the supplied closure to the currently loaded set of plugins.
     NOTE: This does not apply to plugins contained within DestinationPlugins.
     - Parameter closure: A closure that takes an plugin to be operated on as a parameter.

     */
    func apply(closure: (Plugin) -> Void) {
        DataPipeline.shared.analytics.apply(closure: closure)
    }

    /**
     Adds a new plugin to the currently loaded set.

     - Parameter plugin: The plugin to be added.
     - Returns: Returns the name of the supplied plugin.

     */
    @discardableResult
    func add(plugin: Plugin) -> Plugin {
        DataPipeline.shared.analytics.add(plugin: plugin)
    }

    /**
     Adds a new enrichment to the currently loaded set of plugins.

     - Parameter enrichment: The enrichment closure to be added.
     - Returns: Returns the the generated plugin.

     */
    @discardableResult
    func add(enrichment: @escaping EnrichmentClosure) -> Plugin {
        DataPipeline.shared.analytics.add(enrichment: enrichment)
    }

    /**
     Removes and unloads plugins with a matching name from the system.

     - Parameter pluginName: An plugin name.
     */
    func remove(plugin: Plugin) {
        DataPipeline.shared.analytics.remove(plugin: plugin)
    }

    func find<T: Plugin>(pluginType: T.Type) -> T? {
        DataPipeline.shared.analytics.find(pluginType: pluginType)
    }

    func findAll<T: Plugin>(pluginType: T.Type) -> [T]? {
        DataPipeline.shared.analytics.findAll(pluginType: pluginType)
    }

    func find(key: String) -> DestinationPlugin? {
        DataPipeline.shared.analytics.find(key: key)
    }
}
