//
//  LogOutputter.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/9/25.
//


public protocol LogOutputter {
    func output(level: CioLogLevel, _ message: String)
}
