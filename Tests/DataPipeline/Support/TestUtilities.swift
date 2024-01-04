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
