//
//  EventDeliverySummary.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/17/25.
//

import Foundation

/// A summary of the delivery statistics for an event submitted to the event queue.
public struct EventDeliverySummary: Sendable {
    public var sourceEvent: any Sendable
    public var registeredObservers: Int
    public var handlingObservers: Int
    public var arrivalTime: Date
    public var completionTime: Date
}
