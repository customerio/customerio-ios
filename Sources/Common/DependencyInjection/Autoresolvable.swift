//
//  Autoresolvable.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/8/25.
//

public protocol Autoresolvable {
    init(resolver: Resolver) throws
}
