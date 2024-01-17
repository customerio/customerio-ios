@testable import CioDataPipelines
import Foundation
@testable import Segment
import XCTest

// MARK: - Helper Plugins

class OutputReaderPlugin: Plugin {
    let type: PluginType
    var analytics: Analytics?

    var events = [RawEvent]()
    var lastEvent: RawEvent?

    init() {
        self.type = .after
    }

    func execute<T>(event: T?) -> T? where T: RawEvent {
        lastEvent = event
        var eventSummary = ""

        if let event = event {
            eventSummary += " Event type: \(event.type ?? "nil")"
            events.append(event)
            if let event = event as? TrackEvent {
                eventSummary += " Event type: \(event.event)"
            }
        }

        // Prints event summary to help in debugging tests during development
        print("[CIO]-[OutputReaderPlugin] \(eventSummary)")
        return event
    }

    func resetPlugin() {
        events.removeAll()
        lastEvent = nil
    }
}

extension OutputReaderPlugin {
    var identifyEvents: [IdentifyEvent] { events.compactMap { $0 as? IdentifyEvent } }
    var trackEvents: [RawEvent] { events.compactMap { $0 as? TrackEvent } }
    var screenEvents: [RawEvent] { events.compactMap { $0 as? ScreenEvent } }

    var deviceDeleteEvents: [TrackEvent] {
        events
            .compactMap { $0 as? TrackEvent }
            .filter { $0.event == "Device Deleted" }
    }

    var deviceUpdateEvents: [TrackEvent] {
        events
            .compactMap { $0 as? TrackEvent }
            .filter { $0.event == "Device Created or Updated" }
    }
}

extension RawEvent {
    var deviceToken: String? {
        if let context = context?.dictionaryValue {
            return context[keyPath: "device.token"] as? String
        }
        return nil
    }

    var properties: [String: Any]? {
        if let event = self as? TrackEvent {
            return event.properties?.dictionaryValue
        } else if let event = self as? ScreenEvent {
            return event.properties?.dictionaryValue
        }
        return nil
    }
}

// MARK: - Helper Methods

func waitUntilStarted(analytics: Analytics?) {
    guard let analytics = analytics else { return }

    // wait until the startup queue has emptied it's events.
    if let startupQueue = analytics.find(pluginType: StartupQueue.self) {
        while startupQueue.running != true {
            RunLoop.main.run(until: Date.distantPast)
        }
    }
}

/// Attaches and returns plugin only if it wasn't attached previously
func attachPlugin<P: Plugin>(analytics: Analytics?, plugin: P) -> P {
    guard let analytics = analytics else { fatalError("Analytics instance is nil") }

    if analytics.find(pluginType: P.self) != nil {
        fatalError("Plugin \(P.self) is already attached")
    }

    analytics.add(plugin: plugin)
    return plugin
}
