//
//  ConsoleLogOutputter.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/10/25.
//

public struct ConsoleLogOutputter: LogOutputter {
    public func output(level: CioLogLevel, _ message: String) {
        Swift.print("[\(level)] \(message)")
    }
}
