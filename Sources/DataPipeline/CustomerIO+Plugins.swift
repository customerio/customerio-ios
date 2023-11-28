import CioInternalCommon
import Foundation
import Segment

extension CustomerIO {
    /**
     Applies the supplied closure to the currently loaded set of plugins.
     NOTE: This does not apply to plugins contained within DestinationPlugins.
     - Parameter closure: A closure that takes an plugin to be operated on as a parameter.

     */
    func apply(closure: (Plugin) -> Void) {
        CIODataPipeline.shared().apply(closure: closure)
    }

    /**
     Adds a new plugin to the currently loaded set.

     - Parameter plugin: The plugin to be added.
     - Returns: Returns the name of the supplied plugin.

     */
    @discardableResult
    func add(plugin: Plugin) -> Plugin {
        CIODataPipeline.shared().add(plugin: plugin)
    }

    /**
     Adds a new enrichment to the currently loaded set of plugins.

     - Parameter enrichment: The enrichment closure to be added.
     - Returns: Returns the the generated plugin.

     */
    @discardableResult
    func add(enrichment: @escaping EnrichmentClosure) -> Plugin {
        CIODataPipeline.shared().add(enrichment: enrichment)
    }

    /**
     Removes and unloads plugins with a matching name from the system.

     - Parameter pluginName: An plugin name.
     */
    func remove(plugin: Plugin) {
        CIODataPipeline.shared().remove(plugin: plugin)
    }

    func find<T: Plugin>(pluginType: T.Type) -> T? {
        CIODataPipeline.shared().find(pluginType: pluginType)
    }

    func findAll<T: Plugin>(pluginType: T.Type) -> [T]? {
        CIODataPipeline.shared().findAll(pluginType: pluginType)
    }

    func find(key: String) -> DestinationPlugin? {
        CIODataPipeline.shared().find(key: key)
    }
}
