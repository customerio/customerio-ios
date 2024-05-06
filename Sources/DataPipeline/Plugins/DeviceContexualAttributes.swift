import CioAnalytics
import Foundation

// This plugin is used to add contextual data to the device attributes
class DeviceContexualAttributes: EventPlugin {
    var type: PluginType = .enrichment
    var analytics: Analytics?

    func track(event: TrackEvent) -> TrackEvent? {
        var workingEvent = event
        let context = event.context?.dictionaryValue

        if workingEvent.event == "Device Created or Updated" {
            // add selected contextual data to parameters so they end up as device attributes
            if let networkDictionary = context?["network"] as? [String: Any] {
                if let bluetoothValue = networkDictionary["bluetooth"] {
                    workingEvent.properties?[keyPath: "network_bluetooth"] = try? JSON(bluetoothValue)
                }

                if let cellularValue = networkDictionary["cellular"] {
                    workingEvent.properties?[keyPath: "network_cellular"] = try? JSON(cellularValue)
                }

                if let wifiValue = networkDictionary["wifi"] {
                    workingEvent.properties?[keyPath: "network_wifi"] = try? JSON(wifiValue)
                }
            }

            if let screenDictionary = context?["screen"] as? [String: Any] {
                if let widthValue = screenDictionary["width"] {
                    workingEvent.properties?[keyPath: "screen_width"] = try? JSON(widthValue)
                }

                if let heightValue = screenDictionary["height"] {
                    workingEvent.properties?[keyPath: "screen_height"] = try? JSON(heightValue)
                }
            }
            if let value = context?["ip"] {
                workingEvent.properties?[keyPath: "ip"] = try? JSON(value)
            }
            if let value = context?["timezone"] {
                workingEvent.properties?[keyPath: "timezone"] = try? JSON(value)
            }
        }

        return workingEvent
    }
}
