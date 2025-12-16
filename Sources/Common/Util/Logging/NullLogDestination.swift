//
//  NullLogDestination.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/12/25.
//


/// Log Outputter that sends log messages straight to /dev/null.
public struct NullLogDestination: LogDestination {
    
    public init() {}
    
    public func output(message: LogMessage) { }
}
