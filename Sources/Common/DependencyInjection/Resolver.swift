//
//  Resolver.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/8/25.
//

public protocol Resolver {
    var container: DependencyContainer { get }
    func resolve<T>() throws -> T
}
